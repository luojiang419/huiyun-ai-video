import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/film_tabs_bar.dart';
import '../providers/film_project_provider.dart';
import '../constants/app_colors.dart';
import 'film_workshop_screen.dart';

class FilmWorkshopWrapper extends ConsumerStatefulWidget {
  const FilmWorkshopWrapper({super.key});

  @override
  ConsumerState<FilmWorkshopWrapper> createState() => _FilmWorkshopWrapperState();
}

class _FilmWorkshopWrapperState extends ConsumerState<FilmWorkshopWrapper> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final projectState = ref.read(filmProjectProvider);
      if (projectState.currentProject == null) {
        ref.read(filmProjectProvider.notifier).createProject('默认工程', '默认工程');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navbar,
        title: const FilmTabsBar(),
      ),
      body: const FilmWorkshopScreen(),
    );
  }
}
