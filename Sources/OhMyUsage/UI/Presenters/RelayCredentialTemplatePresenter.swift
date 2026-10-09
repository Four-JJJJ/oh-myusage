import Foundation

extension SettingsView {
    enum RelayCredentialTemplateKind {
        case cookie
        case bearer
        case custom(header: String, scheme: String)
    }

    struct RelayCredentialTemplate {
        let kind: RelayCredentialTemplateKind
        let placeholder: String
        let hint: String
    }

}

enum RelayCredentialTemplatePresenter {
    static func build(authHeader: String?, authScheme: String?, language: AppLanguage) -> SettingsView.RelayCredentialTemplate {
        let header = (authHeader ?? "Authorization").trimmingCharacters(in: .whitespacesAndNewlines)
        let scheme = (authScheme ?? "Bearer").trimmingCharacters(in: .whitespacesAndNewlines)

        if header.caseInsensitiveCompare("Cookie") == .orderedSame {
            if language == .zhHans {
                return SettingsView.RelayCredentialTemplate(
                    kind: .cookie,
                    placeholder: "粘贴完整 Cookie Header，例如 session=...; token=...",
                    hint: "这里填写完整 Cookie Header，不是单个字段。"
                )
            } else {
                return SettingsView.RelayCredentialTemplate(
                    kind: .cookie,
                    placeholder: "Paste the full Cookie header, for example session=...; token=...",
                    hint: "Paste the full Cookie header, not a single cookie field."
                )
            }
        }

        if header.caseInsensitiveCompare("Authorization") == .orderedSame &&
            (scheme.isEmpty || scheme.caseInsensitiveCompare("Bearer") == .orderedSame) {
            if language == .zhHans {
                return SettingsView.RelayCredentialTemplate(
                    kind: .bearer,
                    placeholder: "粘贴 Bearer Token，例如 Bearer eyJ... 或 eyJ...",
                    hint: "这里填写 Authorization Bearer 值，带或不带 Bearer 前缀都可以。"
                )
            } else {
                return SettingsView.RelayCredentialTemplate(
                    kind: .bearer,
                    placeholder: "Paste the bearer token, for example Bearer eyJ... or eyJ...",
                    hint: "Paste the Authorization bearer value, with or without the Bearer prefix."
                )
            }
        }

        let normalizedHeader = header.isEmpty ? "Authorization" : header
        let normalizedScheme = scheme
        if language == .zhHans {
            return SettingsView.RelayCredentialTemplate(
                kind: .custom(header: normalizedHeader, scheme: normalizedScheme),
                placeholder: "粘贴 \(normalizedHeader) 的值：\(normalizedScheme.isEmpty ? "<value>" : "\(normalizedScheme) <value>")",
                hint: "这里填写站点要求的自定义请求头值。"
            )
        } else {
            return SettingsView.RelayCredentialTemplate(
                kind: .custom(header: normalizedHeader, scheme: normalizedScheme),
                placeholder: "Paste the \(normalizedHeader) value: \(normalizedScheme.isEmpty ? "<value>" : "\(normalizedScheme) <value>")",
                hint: "Paste the custom header value required by this site."
            )
        }
    }

}
