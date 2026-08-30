#if DEBUG

import SwiftUI

struct DashboardAnimatedBlobLabView: View {
    var body: some View {
        ZStack {
            Color(red: 0.995, green: 0.993, blue: 1.000)
                .ignoresSafeArea()

            DashboardAmbientBlobView()
        }
        .navigationTitle("Dashboard Ambient Blob")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#endif
