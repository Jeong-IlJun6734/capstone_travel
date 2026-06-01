import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

import '../services/naver_image_search_service.dart';
import '../services/naver_local_search_service.dart';
import '../services/naver_map_config.dart';
import '../theme/route_in_palette.dart';

class AddPlacePage extends StatefulWidget {
  const AddPlacePage({super.key, required this.nextPlaceId});

  final int nextPlaceId;

  @override
  State<AddPlacePage> createState() => _AddPlacePageState();
}

class _AddPlacePageState extends State<AddPlacePage> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _moveController = TextEditingController();
  final NaverLocalSearchService _localSearchService =
      const NaverLocalSearchService();
  final NaverImageSearchService _imageSearchService =
      const NaverImageSearchService();

  NaverMapController? _mapController;
  List<NaverLocalPlace> _places = const [];
  List<NaverImageResult> _images = const [];
  NaverLocalPlace? _selectedPlace;
  String? _selectedThumbnailUrl;
  String? _selectedImageUrl;
  String? _searchError;
  bool _isSearching = false;
  bool _isLoadingImages = false;

  @override
  void dispose() {
    _searchController.dispose();
    _noteController.dispose();
    _moveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedPlace = _selectedPlace;

    return Scaffold(
      backgroundColor: RouteInPalette.white,
      appBar: AppBar(title: const Text('장소 추가')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
              child: _SearchField(
                controller: _searchController,
                isSearching: _isSearching,
                onSearch: _searchPlaces,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _SearchMap(
                places: _places,
                selectedPlace: selectedPlace,
                onMapReady: _rememberMapController,
              ),
            ),
            Expanded(
              child: DecoratedBox(
                decoration: const BoxDecoration(color: RouteInPalette.sky),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  children: [
                    if (_searchError != null)
                      _InlineNotice(
                        icon: Icons.error_outline_rounded,
                        text: _searchError!,
                      ),
                    if (_places.isEmpty && !_isSearching) ...[
                      const _InlineNotice(
                        icon: Icons.search_rounded,
                        text: '장소명을 검색하면 지도와 결과 목록이 함께 표시됩니다.',
                      ),
                    ],
                    if (_places.isNotEmpty) ...[
                      Text(
                        '검색 결과',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 10),
                      for (final place in _places) ...[
                        _PlaceSearchCard(
                          place: place,
                          selected: identical(place, selectedPlace),
                          onTap: () => _selectPlace(place),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                    if (selectedPlace != null) ...[
                      const SizedBox(height: 8),
                      _SelectedPlaceEditor(
                        place: selectedPlace,
                        images: _images,
                        selectedThumbnailUrl: _selectedThumbnailUrl,
                        isLoadingImages: _isLoadingImages,
                        noteController: _noteController,
                        moveController: _moveController,
                        onSelectImage: _selectImage,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: FilledButton.icon(
            onPressed: selectedPlace == null ? null : _addSelectedPlace,
            icon: const Icon(Icons.add_location_alt_rounded),
            label: const Text('이 장소를 일정에 추가'),
          ),
        ),
      ),
    );
  }

  Future<void> _searchPlaces() async {
    final query = _searchController.text.trim();
    if (query.isEmpty || _isSearching) return;

    setState(() {
      _isSearching = true;
      _searchError = null;
      _places = const [];
      _selectedPlace = null;
      _images = const [];
      _selectedThumbnailUrl = null;
      _selectedImageUrl = null;
    });

    try {
      final places = await _localSearchService.search(query: query);
      if (!mounted) return;

      setState(() {
        _places = places;
        _isSearching = false;
        _searchError = places.isEmpty ? '검색 결과가 없습니다.' : null;
      });

      if (places.isNotEmpty) {
        await _selectPlace(places.first);
      }
    } on NaverLocalSearchException catch (error) {
      _setSearchError(error.message);
    } catch (error) {
      _setSearchError('장소 검색 중 오류가 발생했습니다.');
    }
  }

  Future<void> _selectPlace(NaverLocalPlace place) async {
    setState(() {
      _selectedPlace = place;
      _noteController.text = place.displayAddress.isEmpty
          ? place.category
          : place.displayAddress;
      _images = const [];
      _selectedThumbnailUrl = null;
      _selectedImageUrl = null;
      _isLoadingImages = true;
    });

    await _focusMap(place);

    try {
      final images = await _imageSearchService.search(
        query:
            '${place.title} ${place.displayAddress} ${place.primaryCategory}',
      );
      if (!mounted || !identical(_selectedPlace, place)) return;

      setState(() {
        _images = images;
        _selectedThumbnailUrl = images.isEmpty ? null : images.first.thumbnail;
        _selectedImageUrl = images.isEmpty ? null : images.first.link;
        _isLoadingImages = false;
      });
    } catch (error) {
      debugPrint('Naver image search failed: $error');
      if (!mounted || !identical(_selectedPlace, place)) return;

      setState(() {
        _isLoadingImages = false;
      });
    }
  }

  void _selectImage(NaverImageResult image) {
    setState(() {
      _selectedThumbnailUrl = image.thumbnail;
      _selectedImageUrl = image.link;
    });
  }

  void _addSelectedPlace() {
    final place = _selectedPlace;
    if (place == null) return;

    Navigator.of(context).pop(
      AddedTripPlaceDraft(
        id: widget.nextPlaceId,
        category: place.primaryCategory,
        name: place.title,
        note: _noteController.text.trim().isEmpty
            ? place.displayAddress
            : _noteController.text.trim(),
        move: _moveController.text.trim().isEmpty
            ? null
            : _moveController.text.trim(),
        address: place.displayAddress,
        link: place.link,
        latitude: place.latitude,
        longitude: place.longitude,
        thumbnailUrl: _selectedThumbnailUrl,
        imageUrl: _selectedImageUrl,
      ),
    );
  }

  void _rememberMapController(NaverMapController controller) {
    _mapController = controller;
  }

  Future<void> _focusMap(NaverLocalPlace place) async {
    final controller = _mapController;
    if (controller == null ||
        place.latitude == null ||
        place.longitude == null) {
      return;
    }

    await controller.updateCamera(
      NCameraUpdate.scrollAndZoomTo(
        target: NLatLng(place.latitude!, place.longitude!),
        zoom: 15,
      ),
    );
  }

  void _setSearchError(String message) {
    if (!mounted) return;

    setState(() {
      _isSearching = false;
      _searchError = message;
    });
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.isSearching,
    required this.onSearch,
  });

  final TextEditingController controller;
  final bool isSearching;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => onSearch(),
      decoration: InputDecoration(
        labelText: '네이버 장소 검색',
        hintText: '예: 서울역 카페, 경복궁',
        filled: true,
        fillColor: RouteInPalette.sky.withValues(alpha: 0.2),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        suffixIcon: IconButton(
          onPressed: isSearching ? null : onSearch,
          icon: isSearching
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.search_rounded),
        ),
      ),
    );
  }
}

class _SearchMap extends StatelessWidget {
  const _SearchMap({
    required this.places,
    required this.selectedPlace,
    required this.onMapReady,
  });

  final List<NaverLocalPlace> places;
  final NaverLocalPlace? selectedPlace;
  final ValueChanged<NaverMapController> onMapReady;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 250,
        width: double.infinity,
        child: !NaverMapConfig.supportsMobileMap
            ? const _MapFallback(
                icon: Icons.phone_android_rounded,
                title: '모바일에서 지도를 확인하세요.',
              )
            : !NaverMapConfig.hasClientId
            ? const _MapFallback(
                icon: Icons.key_rounded,
                title: '네이버 지도 Client ID가 필요합니다.',
              )
            : !NaverMapConfig.isReady
            ? const _MapFallback(
                icon: Icons.map_outlined,
                title: '네이버 지도를 준비하는 중입니다.',
              )
            : NaverMap(
                key: ValueKey(
                  '${places.length}_${selectedPlace?.title ?? 'none'}',
                ),
                options: NaverMapViewOptions(
                  initialCameraPosition: NCameraPosition(
                    target: _initialTarget,
                    zoom: selectedPlace == null ? 11 : 15,
                  ),
                ),
                onMapReady: _addMarkers,
              ),
      ),
    );
  }

  NLatLng get _initialTarget {
    final place = selectedPlace ?? (places.isEmpty ? null : places.first);
    if (place?.latitude != null && place?.longitude != null) {
      return NLatLng(place!.latitude!, place.longitude!);
    }

    return const NLatLng(37.5666102, 126.9783881);
  }

  Future<void> _addMarkers(NaverMapController controller) async {
    onMapReady(controller);
    final markers = <NMarker>{};
    final coords = <NLatLng>[];

    for (final place in places) {
      if (place.latitude == null || place.longitude == null) continue;

      final position = NLatLng(place.latitude!, place.longitude!);
      coords.add(position);
      markers.add(
        NMarker(
          id: 'place_${place.title}_${place.latitude}_${place.longitude}',
          position: position,
          iconTintColor: identical(place, selectedPlace)
              ? RouteInPalette.coral
              : RouteInPalette.denim,
          caption: NOverlayCaption(text: place.title),
        ),
      );
    }

    if (markers.isNotEmpty) {
      await controller.addOverlayAll(markers);
    }

    if (coords.length > 1 && selectedPlace == null) {
      await controller.updateCamera(
        NCameraUpdate.fitBounds(
          NLatLngBounds.from(coords),
          padding: const EdgeInsets.all(42),
        ),
      );
    }
  }
}

class _MapFallback extends StatelessWidget {
  const _MapFallback({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: RouteInPalette.mist,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: RouteInPalette.navy, size: 36),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _PlaceSearchCard extends StatelessWidget {
  const _PlaceSearchCard({
    required this.place,
    required this.selected,
    required this.onTap,
  });

  final NaverLocalPlace place;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: RouteInPalette.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? RouteInPalette.coral : RouteInPalette.white,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.check_circle_rounded : Icons.place_outlined,
                color: selected ? RouteInPalette.coral : RouteInPalette.navy,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      place.primaryCategory,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: RouteInPalette.denim,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (place.displayAddress.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        place.displayAddress,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: RouteInPalette.navy,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedPlaceEditor extends StatelessWidget {
  const _SelectedPlaceEditor({
    required this.place,
    required this.images,
    required this.selectedThumbnailUrl,
    required this.isLoadingImages,
    required this.noteController,
    required this.moveController,
    required this.onSelectImage,
  });

  final NaverLocalPlace place;
  final List<NaverImageResult> images;
  final String? selectedThumbnailUrl;
  final bool isLoadingImages;
  final TextEditingController noteController;
  final TextEditingController moveController;
  final ValueChanged<NaverImageResult> onSelectImage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RouteInPalette.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '선택한 장소',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SelectedThumbnail(url: selectedThumbnailUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      place.displayAddress,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: RouteInPalette.navy,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (isLoadingImages)
            const LinearProgressIndicator()
          else if (images.isNotEmpty)
            SizedBox(
              height: 82,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: images.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final image = images[index];
                  return _ImageChoice(
                    image: image,
                    selected: image.thumbnail == selectedThumbnailUrl,
                    onTap: () => onSelectImage(image),
                  );
                },
              ),
            )
          else
            Text(
              '이미지 검색 결과가 없어 기본 아이콘으로 표시됩니다.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: RouteInPalette.navy,
              ),
            ),
          const SizedBox(height: 14),
          TextField(
            controller: noteController,
            decoration: const InputDecoration(labelText: '메모'),
            maxLines: 2,
          ),
          TextField(
            controller: moveController,
            decoration: const InputDecoration(
              labelText: '이동 정보',
              hintText: '예: 도보 8분',
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectedThumbnail extends StatelessWidget {
  const _SelectedThumbnail({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final url = this.url;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 92,
        height: 92,
        child: url == null
            ? Container(
                color: RouteInPalette.denim,
                child: const Icon(
                  Icons.image_outlined,
                  color: RouteInPalette.white,
                ),
              )
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  color: RouteInPalette.denim,
                  child: const Icon(
                    Icons.broken_image_outlined,
                    color: RouteInPalette.white,
                  ),
                ),
              ),
      ),
    );
  }
}

class _ImageChoice extends StatelessWidget {
  const _ImageChoice({
    required this.image,
    required this.selected,
    required this.onTap,
  });

  final NaverImageResult image;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        width: 82,
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? RouteInPalette.coral : RouteInPalette.mist,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.network(
            image.thumbnail,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const ColoredBox(
              color: RouteInPalette.mist,
              child: Icon(Icons.broken_image_outlined),
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: RouteInPalette.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: RouteInPalette.denim),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: RouteInPalette.navy,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AddedTripPlaceDraft {
  const AddedTripPlaceDraft({
    required this.id,
    required this.category,
    required this.name,
    required this.note,
    this.move,
    this.address,
    this.link,
    this.latitude,
    this.longitude,
    this.thumbnailUrl,
    this.imageUrl,
  });

  final int id;
  final String category;
  final String name;
  final String note;
  final String? move;
  final String? address;
  final String? link;
  final double? latitude;
  final double? longitude;
  final String? thumbnailUrl;
  final String? imageUrl;
}
