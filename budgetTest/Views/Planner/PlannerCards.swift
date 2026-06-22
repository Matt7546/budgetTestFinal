import SwiftUI

extension PlannerView {
    
    
    var availableCard: some View {
        let accentColor =
            plannerAvailable >= 0
            ? AppColors.spendable
            : AppColors.negative
        
        return ZStack {
            
            RoundedRectangle(
                cornerRadius: 34
            )
            .fill(
                LinearGradient(
                    colors: [
                        accentColor.opacity(0.10),
                        AppColors.glassOverlaySurface
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            
            VStack {
                
                HStack {
                    
                    Spacer()
                    
                    ZStack {
                        
                        RoundedRectangle(
                            cornerRadius: 22
                        )
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppColors.glassSubtleHighlight,
                                    accentColor.opacity(0.15)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(
                            width: 110,
                            height: 90
                        )
                        
                        RoundedRectangle(
                            cornerRadius: 22
                        )
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppColors.glassOverlayWhite,
                                    accentColor.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(
                            width: 110,
                            height: 90
                        )
                        .offset(
                            x: 12,
                            y: 10
                        )
                    }
                    .rotationEffect(
                        .degrees(-12)
                    )
                    .opacity(0.55)
                }
                
                Spacer()
            }
            .padding(.top, 18)
            .padding(.trailing, 22)
            
            VStack(
                alignment: .leading,
                spacing: 8
            ) {
                
                HStack {
                    
                    ZStack {
                        
                        Circle()
                            .fill(
                                accentColor.opacity(0.12)
                            )
                            .frame(
                                width: 34,
                                height: 34
                            )
                        
                        Image(
                            systemName: "wallet.pass.fill"
                        )
                        .font(
                            .system(
                                size: 15,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(accentColor)
                    }
                    
                    Text("Safe to Spend")
                        .font(.headline)
                        .foregroundStyle(AppColors.secondaryText)
                    
                    Spacer()
                }
                
                MetricValue(
                    plannerAvailable,
                    font: .system(
                        size: 50,
                        weight: .bold,
                        design: .rounded
                    ),
                    color: accentColor,
                    minimumScaleFactor: 0.7,
                    lineLimit: 1
                )

                Text("Current snapshot")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.secondaryText)
                
                Spacer()
            }
            .padding(.top, 24)
            .padding(.horizontal, 24)
        }
        .frame(height: 180)
        .overlay(
            RoundedRectangle(
                cornerRadius: 34
            )
            .stroke(
                AppColors.glassHighlight,
                lineWidth: 1
            )
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 34
            )
        )
        .shadow(
            color: accentColor.opacity(0.08),
            radius: 20,
            y: 10
        )
    }
}
