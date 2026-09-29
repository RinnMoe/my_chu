import 'package:flutter/material.dart';

/// Material 3 startup surface used while the host restores its state.
class AdaptiveStartupSplash extends StatelessWidget {
  const AdaptiveStartupSplash({super.key});

  Widget _buildingArtwork() {
    return Center(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final preferredWidth = constraints.maxWidth * 0.62;
          final width = preferredWidth < 320.0 ? preferredWidth : 320.0;
          return Image.asset(
            'assets/splash/campus_building.png',
            width: width,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            semanticLabel: 'MyCHU 长安大学校园建筑',
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _buildingArtwork(),
          Positioned(
            left: 0,
            right: 0,
            bottom: 96,
            child: Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
