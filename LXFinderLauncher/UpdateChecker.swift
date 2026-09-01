//
//  UpdateChecker.swift
//  LXFinderLauncher
//
//  Created by 启业云03 on 2026/9/1.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.linx.LXFinderLauncher", category: "Update")

/// 更新信息：版本 + 下载地址 + 更新说明。
struct UpdateInfo {
    let version: String
    let downloadURL: URL
    let notes: String?
}

/// 检查更新时的错误。
enum UpdateCheckError: LocalizedError {
    case invalidURL
    case invalidResponse
    case network(Error)
    case decode(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "更新地址无效"
        case .invalidResponse: return "更新服务器返回的数据格式不对"
        case .network(let error): return "网络请求失败：\(error.localizedDescription)"
        case .decode(let error): return "更新信息解析失败：\(error.localizedDescription)"
        }
    }
}

/// 轻量更新检查：请求一个 JSON 对比版本号。
///
/// 免费分发（未签名）无法用 Sparkle（它强制要求签名），改用 URLSession 请求一个
/// 静态 JSON —— 无需签名、无需服务器逻辑，放到任何静态托管即可。
enum UpdateChecker {

    // MARK: - 更新源（发布时替换成你自己的地址）

    /// ⚠️ TODO 发布前改成你自己的 JSON 地址。
    ///
    /// 本工程采用「GitHub Releases + Gist」方案：
    ///   · update.json 放在 Gist（github.com → Gist → New gist，
    ///     内容见工程内 docs/update.json.example）。
    ///   · 把 Gist 的 Raw 链接贴到这里，格式：
    ///       https://gist.githubusercontent.com/<你的用户名>/<gist-id>/raw/update.json
    ///
    /// JSON 里的 downloadURL 用 GitHub Releases 的固定「最新版」链接：
    ///       https://github.com/<你的用户名>/LXFinderLauncher/releases/latest/download/LXFinderLauncher.zip
    /// 该链接永远指向「最新一个 Release 里名为 LXFinderLauncher.zip 的文件」，
    /// 因此每次发版上传同名 zip 即可，JSON 里的下载地址无需改动。
    static let feedURL = URL(string: "https://gist.githubusercontent.com/YOUR_USERNAME/GIST_ID/raw/update.json")!

    /// 当前 App 版本号（工程 Info.plist 的 CFBundleShortVersionString）。
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    // MARK: - 检查

    /// 异步检查更新，结果通过 completion 回调（任意线程，调用方自行回主线程）。
    static func check(completion: @escaping (Result<UpdateInfo, Error>) -> Void) {
        let task = URLSession.shared.dataTask(with: feedURL) { data, response, error in
            if let error {
                completion(.failure(UpdateCheckError.network(error)))
                return
            }
            guard let data, (response as? HTTPURLResponse)?.statusCode == 200 else {
                completion(.failure(UpdateCheckError.invalidResponse))
                return
            }
            do {
                // JSON 用 [String: String] 解码，只取需要的键，顺序无关。
                let dict = try JSONDecoder().decode([String: String].self, from: data)
                guard let version = dict["version"],
                      let urlString = dict["downloadURL"],
                      let url = URL(string: urlString) else {
                    completion(.failure(UpdateCheckError.invalidResponse))
                    return
                }
                let info = UpdateInfo(version: version, downloadURL: url, notes: dict["notes"])
                logger.info("检查更新：服务器版本 \(info.version)，当前 \(currentVersion)")
                completion(.success(info))
            } catch {
                completion(.failure(UpdateCheckError.decode(error)))
            }
        }
        task.resume()
    }

    // MARK: - 版本比较

    /// `a` 是否比 `b` 新（按 major.minor.patch 逐段数字比较，忽略前导 v）。
    static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ version: String) -> [Int] {
            version
                .split(separator: ".")
                .map { Int($0.filter { $0.isNumber }) ?? 0 }
        }
        let pa = parts(a)
        let pb = parts(b)
        let count = max(pa.count, pb.count)
        for i in 0..<count {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false   // 版本完全相同，或 a 更旧
    }
}
