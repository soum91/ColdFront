import Foundation
import CryptoKit
import Security

/// Talks to the ConnectLife cloud (the same backend the official app uses).
/// Flow: Gigya login -> Gigya JWT -> HijuConn OAuth code -> access token -> signed gateway calls.
actor ConnectLifeClient {

    enum ClientError: LocalizedError {
        case badCredentials(String)
        case termsNotAccepted
        case gateway(code: String, message: String)
        case unexpected(String)

        var errorDescription: String? {
            switch self {
            case .badCredentials(let m): return "Login failed: \(m)"
            case .termsNotAccepted:
                return "ConnectLife wants you to accept updated Terms & Conditions. Open the official app once, accept them, then try again."
            case .gateway(let code, let message): return "Server error \(code): \(message)"
            case .unexpected(let m): return m
            }
        }
    }

    // MARK: Endpoints and app identity (from the official app, via oyvindwe/connectlife research)

    private enum K {
        static let gigyaAPIKey = "4_yhTWQmHFpZkQZDSV1uV-_A"
        static let gigyaLogin = URL(string: "https://accounts.eu1.gigya.com/accounts.login")!
        static let gigyaJWT = URL(string: "https://accounts.eu1.gigya.com/accounts.getJWT")!

        static let oauthAuthorize = URL(string: "https://oauth.hijuconn.com/oauth/authorize")!
        static let oauthToken = URL(string: "https://oauth.hijuconn.com/oauth/token")!
        static let clientID = "5065059336212"
        static let clientSecret = "07swfKgvJhC3ydOUS9YV_SwVz0i4LKqlOLGNUukYHVMsJRF1b-iWeUGcNlXyYCeK"
        static let redirectURI = "https://api.connectlife.io/swagger/oauth2-redirect.html"

        static let gateway = "https://clife-eu-gateway.hijuconn.com"
        static let deviceList = URL(string: gateway + "/clife-svc/pu/get_device_status_list")!
        static let propertySet = URL(string: gateway + "/device/pu/property/set")!
        static let energy = URL(string: gateway + "/clife-svc/pu/air_duct_energy")!

        static let appID = "47110565134383"
        static let appSecret = "yOzhz6junYno-nmULM3Wr7PU_dpSZN22ZdluvVWZ4uW5ZwwG8fIGCHTbrhcnU-iv"
        static let signSuffix = "D9519A4B756946F081B7BB5B5E8D1197"
        static let languageID = "12"
        static let timezone = "1.0"
        static let version = "5.0"

        static let invalidToken = "100026"
        static let randStrFailed = "101005"
        static let termsPending = 206001

        /// Gateway RSA public key, PKCS#1 DER (base64).
        static let publicKeyDER = "MIIBCgKCAQEAyyWrNG6q475HIHu7sMVuvHof6vlgPeixmxa4EL/UsvVvHPz33NnWoQetQqit9TBNzUjMXw0KlY9PXM4iqHUUU+dSyNDq1jZWIiJ2C2FccppswJtIKL3NRMFvT9PFh6NlP/4FUcQKojgKFbF7KaccJPKYHlwaO7qgoIjLxAHlSOXGpucJcOkPzT2EqsSVnW8sn8kenvNmghXDayhgxsh6AyxK4kehJplEnmX/iYCfNoFXknGcLqFWYccgBz3fybvx30C/0IgU1980L8QsUAv5esZmN8ugnbRgLRxKRlkQQLxQAiZMZdKTAx665YflT3YMHJvEFE8c2XFgoxHzSMc4BwIDAQAB"
    }

    private let session: URLSession
    private var username: String
    private var password: String

    private var accessToken: String?
    private var refreshToken: String?
    private var expires: Date = .distantPast

    private lazy var publicKey: SecKey? = {
        guard let data = Data(base64Encoded: K.publicKeyDER) else { return nil }
        let attrs: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits: 2048
        ]
        return SecKeyCreateWithData(data as CFData, attrs as CFDictionary, nil)
    }()

    init(username: String, password: String) {
        self.username = username
        self.password = password
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: cfg)
    }

    // MARK: Public API

    func login() async throws {
        accessToken = nil
        refreshToken = nil
        expires = .distantPast
        try await fullLogin()
    }

    func appliances() async throws -> [Appliance] {
        let resp = try await gateway(K.deviceList, payload: [:], method: "GET")
        guard let list = resp["deviceList"] as? [[String: Any]] else {
            throw ClientError.unexpected("Device list missing from response")
        }
        return list.compactMap(Appliance.init(json:))
    }

    func set(puid: String, properties: [String: String]) async throws {
        _ = try await gateway(K.propertySet, payload: ["puid": puid, "properties": properties], method: "POST")
    }

    /// Today's / this week's energy for air conditioners. Returns kWh total and per-bucket curve.
    func energy(for a: Appliance, stat: String) async throws -> (total: Double?, curve: [String: Double]) {
        let (start, end) = Self.dateRange(stat)
        let resp = try await gateway(K.energy, payload: [
            "puid": a.puid,
            "deviceType": a.typeCode,
            "featureCode": a.featureCode,
            "statType": stat,
            "dateStart": start,
            "dateEnd": end,
            "curve": "1"
        ], method: "POST")
        let data = resp["resultData"] as? [String: Any] ?? [:]
        let total = Double("\(data["electricTotal"] ?? "")")
        var curve: [String: Double] = [:]
        for (k, v) in (data["electricCurve"] as? [String: Any] ?? [:]) where k != "all" {
            if let d = Double("\(v)") { curve[k] = d }
        }
        return (total, curve)
    }

    // MARK: Auth

    private func ensureToken() async throws {
        if accessToken != nil, expires > Date() { return }
        if let rt = refreshToken {
            do {
                try await tokenRequest(["grant_type": "refresh_token", "refresh_token": rt])
                return
            } catch {
                // fall through to full login
            }
        }
        try await fullLogin()
    }

    private func fullLogin() async throws {
        // 1. Gigya login
        let login = try await postForm(K.gigyaLogin, [
            "loginID": username, "password": password, "APIKey": K.gigyaAPIKey
        ])
        if let code = login["errorCode"] as? Int, code != 0 {
            if code == K.termsPending { throw ClientError.termsNotAccepted }
            let msg = (login["errorDetails"] as? String) ?? (login["errorMessage"] as? String) ?? "code \(code)"
            throw ClientError.badCredentials(msg)
        }
        guard let uid = login["UID"] as? String,
              let info = login["sessionInfo"] as? [String: Any],
              let cookie = info["cookieValue"] as? String else {
            throw ClientError.unexpected("Unexpected login response")
        }

        // 2. JWT
        let jwt = try await postForm(K.gigyaJWT, ["APIKey": K.gigyaAPIKey, "login_token": cookie])
        guard let idToken = jwt["id_token"] as? String else {
            throw ClientError.unexpected("No id_token from Gigya")
        }

        // 3. OAuth authorize -> code
        var req = URLRequest(url: K.oauthAuthorize)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_id": K.clientID,
            "redirect_uri": K.redirectURI,
            "idToken": idToken,
            "response_type": "code",
            "thirdType": "CDC",
            "thirdClientId": uid
        ])
        let auth = try await send(req)
        guard let code = auth["code"] as? String else {
            throw ClientError.unexpected("No authorization code")
        }

        // 4. Token
        try await tokenRequest(["grant_type": "authorization_code", "code": code])
    }

    private func tokenRequest(_ extra: [String: String]) async throws {
        var form = ["client_id": K.clientID, "client_secret": K.clientSecret, "redirect_uri": K.redirectURI]
        form.merge(extra) { $1 }
        let body = try await postForm(K.oauthToken, form)
        guard let at = body["access_token"] as? String else {
            throw ClientError.unexpected("No access token")
        }
        let expiresIn = Double("\(body["expires_in"] ?? 3600)") ?? 3600
        accessToken = at
        refreshToken = (body["refresh_token"] as? String) ?? refreshToken
        expires = Date().addingTimeInterval(expiresIn - 90)
    }

    // MARK: Gateway

    private func gateway(_ url: URL, payload: [String: Any], method: String,
                         allowReauth: Bool = true, allowRandRetry: Bool = true) async throws -> [String: Any] {
        try await ensureToken()
        guard let token = accessToken else { throw ClientError.unexpected("Not logged in") }

        var data: [String: Any] = [
            "accessToken": token,
            "appId": K.appID,
            "appSecret": K.appSecret,
            "languageId": K.languageID,
            "randStr": Self.randHex(),
            "timeStamp": String(Int64(Date().timeIntervalSince1970 * 1000)),
            "timezone": K.timezone,
            "version": K.version
        ]
        data.merge(payload) { $1 }
        data["sign"] = try sign(data)

        var req: URLRequest
        if method == "GET" {
            var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            comps.queryItems = data.keys.sorted().map { URLQueryItem(name: $0, value: "\(data[$0]!)") }
            // URLQueryItem leaves '+' and '/' alone, the server would read '+' as a space.
            comps.percentEncodedQuery = comps.percentEncodedQuery?
                .replacingOccurrences(of: "+", with: "%2B")
                .replacingOccurrences(of: "/", with: "%2F")
            req = URLRequest(url: comps.url!)
            req.httpMethod = "GET"
        } else {
            req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: data, options: [.sortedKeys, .withoutEscapingSlashes])
        }
        req.setValue("ColdFront/1.0", forHTTPHeaderField: "User-Agent")

        let body = try await send(req)
        guard let resp = body["response"] as? [String: Any] else {
            throw ClientError.unexpected("Malformed gateway response")
        }
        let result = "\(resp["resultCode"] ?? "0")"
        if result == "0" { return resp }

        let err = "\(resp["errorCode"] ?? "?")"
        let desc = (resp["errorDesc"] as? String) ?? "Unknown error"
        if err == K.invalidToken && allowReauth {
            try await login()
            return try await gateway(url, payload: payload, method: method, allowReauth: false, allowRandRetry: allowRandRetry)
        }
        if err == K.randStrFailed && allowRandRetry {
            return try await gateway(url, payload: payload, method: method, allowReauth: allowReauth, allowRandRetry: false)
        }
        throw ClientError.gateway(code: err, message: desc)
    }

    /// sign = base64( RSA_PKCS1v15( SHA256( "k1=v1&k2=v2...<suffix>" ) ) ), keys sorted, nested objects as compact JSON.
    private func sign(_ data: [String: Any]) throws -> String {
        let parts: [String] = try data.keys.sorted().filter { $0 != "sign" }.map { key in
            let v = data[key]!
            if v is [String: Any] || v is [Any] {
                let json = try JSONSerialization.data(withJSONObject: v, options: [.sortedKeys, .withoutEscapingSlashes])
                return "\(key)=\(String(decoding: json, as: UTF8.self))"
            }
            return "\(key)=\(v)"
        }
        let digest = Data(SHA256.hash(data: Data((parts.joined(separator: "&") + K.signSuffix).utf8)))
        guard let key = publicKey else { throw ClientError.unexpected("Bad gateway key") }
        var error: Unmanaged<CFError>?
        guard let enc = SecKeyCreateEncryptedData(key, .rsaEncryptionPKCS1, digest as CFData, &error) else {
            throw ClientError.unexpected("Signing failed")
        }
        return (enc as Data).base64EncodedString()
    }

    // MARK: HTTP helpers

    private func postForm(_ url: URL, _ form: [String: String]) async throws -> [String: Any] {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        req.httpBody = form.map { k, v in
            "\(k.addingPercentEncoding(withAllowedCharacters: allowed)!)=\(v.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&").data(using: .utf8)
        return try await send(req)
    }

    private func send(_ req: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let text = String(decoding: data.prefix(200), as: UTF8.self)
            throw ClientError.unexpected("HTTP \(status) from \(req.url?.host ?? "server"): \(text)")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClientError.unexpected("Non-JSON response from \(req.url?.host ?? "server")")
        }
        return obj
    }

    private static func randHex() -> String {
        (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }

    private static func dateRange(_ stat: String) -> (String, String) {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        let now = Date()
        switch stat {
        case "week":
            let start = cal.dateInterval(of: .weekOfYear, for: now)!.start
            return (f.string(from: start), f.string(from: cal.date(byAdding: .day, value: 6, to: start)!))
        case "month":
            let iv = cal.dateInterval(of: .month, for: now)!
            return (f.string(from: iv.start), f.string(from: cal.date(byAdding: .day, value: -1, to: iv.end)!))
        default:
            return (f.string(from: now), f.string(from: now))
        }
    }
}
