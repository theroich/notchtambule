//
//  JWTPromptView.swift
//  NotchTubeAudio
//

import SwiftUI

/// Vista del prompt del notch para inspeccionar un JWT decodificado sin verificar su firma.
@MainActor
struct JWTPromptView: View {
    let jwt: DecodedJWT
    let onCopyHeader: () -> Void
    let onCopyPayload: () -> Void
    let onCopyAll: () -> Void
    let onClose: () -> Void

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            warningBanner

            if hasMetadataPills {
                metadataPillsRow
            }

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 8) {
                    jsonSection(
                        title: L10n.string("plugin.developer_toolkit.jwt.header"),
                        content: jwt.formattedHeader
                    )
                    jsonSection(
                        title: L10n.string("plugin.developer_toolkit.jwt.payload"),
                        content: jwt.formattedPayload
                    )
                }
            }
            .frame(maxHeight: 190)

            Text(L10n.string("plugin.developer_toolkit.jwt.sensitive_notice"))
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(2)

            actionBar
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    private var warningBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.yellow)

            Text(L10n.string("plugin.developer_toolkit.jwt.warning_unverified"))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.yellow.opacity(0.95))
                .lineLimit(1)

            Spacer(minLength: 0)

            if jwt.isExpired() {
                Text(L10n.string("plugin.developer_toolkit.jwt.expired"))
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.orange.opacity(0.18)))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.yellow.opacity(0.12))
        )
    }

    private var hasMetadataPills: Bool {
        jwt.algorithm != nil
            || jwt.expiresAt != nil
            || jwt.issuedAt != nil
            || jwt.issuer != nil
            || jwt.subject != nil
    }

    private var metadataPillsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if let alg = jwt.algorithm {
                    metadataPill(label: "alg", value: alg)
                }
                if let exp = jwt.expiresAt {
                    metadataPill(
                        label: "exp",
                        value: Self.dateFormatter.string(from: exp)
                    )
                }
                if let iat = jwt.issuedAt {
                    metadataPill(
                        label: "iat",
                        value: Self.dateFormatter.string(from: iat)
                    )
                }
                if let nbf = jwt.notBefore {
                    metadataPill(
                        label: "nbf",
                        value: Self.dateFormatter.string(from: nbf)
                    )
                }
                if let iss = jwt.issuer {
                    metadataPill(label: "iss", value: iss)
                }
                if let sub = jwt.subject {
                    metadataPill(label: "sub", value: sub)
                }
                if let aud = jwt.audience {
                    metadataPill(label: "aud", value: aud)
                }
            }
        }
    }

    private func metadataPill(label: String, value: String) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
            Text(value)
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(Capsule().fill(.white.opacity(0.10)))
    }

    private func jsonSection(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(.white.opacity(0.65))
                .textCase(.uppercase)

            Text(content)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.white.opacity(0.92))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(7)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(.white.opacity(0.08))
                )
        }
    }

    private var actionBar: some View {
        HStack(spacing: 6) {
            copyButton(
                title: L10n.string("plugin.developer_toolkit.jwt.copy_header"),
                action: onCopyHeader
            )
            copyButton(
                title: L10n.string("plugin.developer_toolkit.jwt.copy_payload"),
                action: onCopyPayload
            )
            copyButton(
                title: L10n.string("plugin.developer_toolkit.jwt.copy_all"),
                action: onCopyAll
            )

            Spacer(minLength: 0)

            Button(action: onClose) {
                Text(L10n.string("plugin.developer_toolkit.jwt.close"))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4.5)
                    .background(Capsule().fill(.white))
            }
            .buttonStyle(.plain)
        }
    }

    private func copyButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 8)
                .padding(.vertical, 4.5)
                .background(Capsule().fill(.white.opacity(0.14)))
        }
        .buttonStyle(.plain)
    }
}
