//
//  Route+Destination.swift
//  PrototipoApp
//
//  Qué pantalla abre cada `Route`. Reemplaza los segues "show" del storyboard.
//

import SwiftUI

extension Route {
    @ViewBuilder var destination: some View {
        switch self {
        case .reportDetail(let id): ReportDetailView(id: id)
        case .settings: SettingsView()
        case .editProfile: EditProfileView()
        case .privacy: PrivacyView()
        case .changePassword: ChangePasswordView()
        case .signOut: SignOutView()
        case .guide: SecurityGuideView()
        case .article(let articulo): ArticleView(articulo: articulo)
        case .stats: CommunityStatsView()
        case .report(let prefill): ReportView(modo: .nuevo(prefill))
        case .editReport(let id): ReportView(modo: .editar(id))
        case .reportSuccess(let id): ReportSuccessView(id: id)
        case .privacyNotice: PrivacyNoticeView()
        case .notifications: NotificationsView()
        case .deleteAccount: DeleteAccountView()
        case .adminQueue: AdminQueueView()
        case .adminReview(let id): AdminReviewView(id: id)
        case .ownerUsers: OwnerUsersView()
        case .publicProfile(let id): PublicProfileView(id: id)
        case .verificarEnlace: VerificarEnlaceView()
        }
    }
}
