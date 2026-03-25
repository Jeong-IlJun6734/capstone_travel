import 'package:flutter/material.dart';

import '../widgets/split_panel.dart';

class IndoorNavigationPage extends StatelessWidget {
  const IndoorNavigationPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('실내 길찾기'),
        backgroundColor: Colors.transparent,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Expanded(
              child: SplitPanel(
                title: '카메라',
                subtitle: '실시간 카메라 화면이 표시될 영역',
                icon: Icons.camera_alt_outlined,
                accent: const Color(0xFFCC5A2B),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.videocam_outlined,
                        size: 56,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '카메라 프리뷰',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SplitPanel(
                title: '이미지',
                subtitle: '하단 참조 이미지 또는 지도 영역',
                icon: Icons.image_outlined,
                accent: const Color(0xFF355C9A),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.photo_size_select_large_outlined,
                        size: 56,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '이미지 뷰',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
