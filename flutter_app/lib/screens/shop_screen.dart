import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/game_service.dart';

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final game = context.read<GameService>();
      game.requestWallet();
      game.requestShopItems();
      game.requestInventory();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFFF8F4F6),
                Color(0xFFF0E8F0),
                Color(0xFFE8F0F8),
              ],
            ),
          ),
          child: SafeArea(
            child: Consumer<GameService>(
              builder: (context, game, _) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  _maybeShowPurchaseDialog(context, game);
                });
                return Column(
                  children: [
                    _buildTopBar(context, game),
                    _buildWalletBar(game),
                    const SizedBox(height: 8),
                    _buildTabs(),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildShopTab(game),
                          _buildInventoryTab(game),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, GameService game) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back),
            color: const Color(0xFF8A7A72),
          ),
          const SizedBox(width: 4),
          const Text(
            '상점',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF5A4038),
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () {
              game.requestWallet();
              game.requestShopItems();
              game.requestInventory();
            },
            icon: const Icon(Icons.refresh),
            color: const Color(0xFF8A7A72),
          ),
        ],
      ),
    );
  }

  Widget _buildWalletBar(GameService game) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0D8D4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.monetization_on, color: Color(0xFFFFB74D)),
          const SizedBox(width: 6),
          Text(
            '${game.gold} 골드',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF5A4038),
            ),
          ),
          const Spacer(),
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFE57373), size: 18),
          const SizedBox(width: 4),
          Text(
            '탈주 ${game.leaveCount}',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF9A6A6A),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const TabBar(
        labelColor: Color(0xFF5A4038),
        unselectedLabelColor: Color(0xFF9A8E8A),
        indicatorColor: Color(0xFFB9A8A1),
        tabs: [
          Tab(text: '상점'),
          Tab(text: '인벤토리'),
        ],
      ),
    );
  }

  Widget _buildShopTab(GameService game) {
    if (game.shopLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (game.shopError != null) {
      return Center(
        child: Text(
          game.shopError!,
          style: const TextStyle(color: Color(0xFFCC6666)),
        ),
      );
    }
    if (game.shopItems.isEmpty) {
      return const Center(
        child: Text(
          '상점 아이템이 없어요',
          style: TextStyle(color: Color(0xFF9A8E8A)),
        ),
      );
    }

    return DefaultTabController(
      length: 5,
      child: Column(
        children: [
          const SizedBox(height: 8),
          _buildCategoryTabs(
            const ['전체', '배너', '칭호', '테마', '유틸'],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildShopList(context, game, _filterShop(game.shopItems, 'all')),
                _buildShopList(context, game, _filterShop(game.shopItems, 'banner')),
                _buildShopList(context, game, _filterShop(game.shopItems, 'title')),
                _buildShopList(context, game, _filterShop(game.shopItems, 'theme')),
                _buildShopList(context, game, _filterShop(game.shopItems, 'utility')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShopList(
    BuildContext context,
    GameService game,
    List<Map<String, dynamic>> items,
  ) {
    if (items.isEmpty) {
      return const Center(
        child: Text(
          '아이템이 없어요',
          style: TextStyle(color: Color(0xFF9A8E8A)),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _buildShopItem(context, game, items[index]),
    );
  }

  Widget _buildShopItem(
    BuildContext context,
    GameService game,
    Map<String, dynamic> item,
  ) {
    final name = item['name']?.toString() ?? '';
    final price = item['price'] ?? 0;
    final isSeason = item['is_season'] == true;
    final isPermanent = item['is_permanent'] == true;
    final durationDays = item['duration_days'];
    final category = item['category']?.toString() ?? '';
    final itemKey = item['item_key']?.toString() ?? '';
    final canBuy = game.gold >= price;
    final owned = game.inventoryItems.any((i) => i['item_key'] == itemKey);

    return InkWell(
      onTap: () => _showItemDetailDialog(context, item),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.95),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE0D8D4)),
        ),
        child: Row(
          children: [
            _buildItemThumbnail(category, name, isSeason, itemKey),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF5A4038),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _buildItemTag(isSeason, isPermanent, durationDays),
                    style: const TextStyle(fontSize: 12, color: Color(0xFF8A7A72)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (owned && isPermanent)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDE7F6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  '보유중',
                  style: TextStyle(fontSize: 12, color: Color(0xFF7E57C2), fontWeight: FontWeight.w600),
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$price G',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF4A4080),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 28,
                    child: ElevatedButton(
                      onPressed: canBuy
                          ? () {
                              if (owned) {
                                _showExtendConfirmDialog(context, game, item);
                              } else {
                                game.buyItem(itemKey);
                              }
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: owned
                            ? const Color(0xFFBBDEFB)
                            : const Color(0xFFC7E6D0),
                        foregroundColor: owned
                            ? const Color(0xFF1565C0)
                            : const Color(0xFF3A5A40),
                        disabledBackgroundColor: const Color(0xFFE0E0E0),
                        disabledForegroundColor: const Color(0xFF9A9A9A),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      child: Text(owned ? '연장' : '구매', style: const TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void _showExtendConfirmDialog(BuildContext context, GameService game, Map<String, dynamic> item) {
    final name = item['name']?.toString() ?? '';
    final itemKey = item['item_key']?.toString() ?? '';
    final price = item['price'] ?? 0;
    final durationDays = item['duration_days'] ?? 0;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('기간 연장'),
        content: Text(
          '이미 보유하고 있는 아이템입니다.\n$name의 기간을 ${durationDays}일 연장하시겠습니까?\n\n비용: $price 골드',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              game.buyItem(itemKey);
            },
            child: const Text('연장하기'),
          ),
        ],
      ),
    );
  }

  Widget _buildInventoryTab(GameService game) {
    if (game.inventoryLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (game.inventoryError != null) {
      return Center(
        child: Text(
          game.inventoryError!,
          style: const TextStyle(color: Color(0xFFCC6666)),
        ),
      );
    }
    if (game.inventoryItems.isEmpty) {
      return const Center(
        child: Text(
          '보유한 아이템이 없어요',
          style: TextStyle(color: Color(0xFF9A8E8A)),
        ),
      );
    }

    return DefaultTabController(
      length: 6,
      child: Column(
        children: [
          const SizedBox(height: 8),
          _buildCategoryTabs(
            const ['전체', '배너', '칭호', '테마', '유틸', '시즌'],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildInventoryList(_filterInventory(game.inventoryItems, 'all')),
                _buildInventoryList(_filterInventory(game.inventoryItems, 'banner')),
                _buildInventoryList(_filterInventory(game.inventoryItems, 'title')),
                _buildInventoryList(_filterInventory(game.inventoryItems, 'theme')),
                _buildInventoryList(_filterInventory(game.inventoryItems, 'utility')),
                _buildInventoryList(_filterInventory(game.inventoryItems, 'season')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInventoryList(List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return const Center(
        child: Text(
          '아이템이 없어요',
          style: TextStyle(color: Color(0xFF9A8E8A)),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _buildInventoryItem(context, items[index]),
    );
  }

  Widget _buildInventoryItem(BuildContext context, Map<String, dynamic> item) {
    final game = context.read<GameService>();
    final name = item['name']?.toString() ?? '';
    final category = item['category']?.toString() ?? '';
    final isActive = item['is_active'] == true;
    final effectType = item['effect_type']?.toString() ?? '';
    final isConsumable = effectType == 'leave_count_reduce' || category == 'utility';
    final expiresAt = item['expires_at'];
    final expiresText = expiresAt != null ? _formatExpire(expiresAt) : null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0D8D4)),
      ),
      child: Row(
        children: [
          _buildItemThumbnail(category, name, item['is_season'] == true, item['item_key']?.toString()),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF5A4038),
                        ),
                      ),
                    ),
                    if (isActive)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDDECF7),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          '사용중',
                          style: TextStyle(fontSize: 11, color: Color(0xFF3E6D8E)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  expiresText ?? '영구 보유',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF8A7A72)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 28,
            child: ElevatedButton(
              onPressed: () {
                final key = item['item_key']?.toString() ?? '';
                if (isConsumable) {
                  game.useItem(key);
                } else {
                  game.equipItem(key);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: isConsumable ? const Color(0xFFFFCC80) : const Color(0xFFB3E5FC),
                foregroundColor: const Color(0xFF5A4038),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: Text(
                isConsumable ? '사용' : '장착',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryIcon(String category) {
    IconData icon = Icons.category;
    Color color = const Color(0xFFB0BEC5);
    switch (category) {
      case 'banner':
        icon = Icons.flag;
        color = const Color(0xFFF5B8C0);
        break;
      case 'title':
        icon = Icons.badge;
        color = const Color(0xFFB39DDB);
        break;
      case 'theme':
        icon = Icons.palette;
        color = const Color(0xFF81C784);
        break;
      case 'utility':
        icon = Icons.handyman;
        color = const Color(0xFFFFB74D);
        break;
      case 'season':
        icon = Icons.emoji_events;
        color = const Color(0xFFFFD54F);
        break;
    }
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 18),
    );
  }

  Widget _buildItemThumbnail(String category, String name, bool isSeason, [String? itemKey]) {
    final style = _thumbnailStyleByKey(itemKey ?? '', category);
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: style['gradient'] as List<Color>,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: (style['borderColor'] as Color?) ?? const Color(0xFFE6DDD8)),
      ),
      child: Stack(
        children: [
          Center(
            child: Icon(
              style['icon'] as IconData,
              color: style['iconColor'] as Color,
              size: 26,
            ),
          ),
          if (isSeason)
            Positioned(
              right: 2,
              top: 2,
              child: Container(
                width: 16,
                height: 16,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFFE08A), width: 0.5),
                ),
                child: const Text(
                  'S',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Map<String, Object> _thumbnailStyleByKey(String itemKey, String category) {
    // Item-specific thumbnails
    switch (itemKey) {
      // Banners
      case 'banner_pastel':
        return {
          'icon': Icons.auto_awesome,
          'iconColor': const Color(0xFFD4A0C0),
          'gradient': [const Color(0xFFFCE4EC), const Color(0xFFF3E5F5)],
          'borderColor': const Color(0xFFF8BBD0),
        };
      case 'banner_blossom':
        return {
          'icon': Icons.local_florist,
          'iconColor': const Color(0xFFE91E63),
          'gradient': [const Color(0xFFFCE4EC), const Color(0xFFF8BBD0)],
          'borderColor': const Color(0xFFF48FB1),
        };
      case 'banner_mint':
        return {
          'icon': Icons.spa,
          'iconColor': const Color(0xFF26A69A),
          'gradient': [const Color(0xFFE0F2F1), const Color(0xFFB2DFDB)],
          'borderColor': const Color(0xFF80CBC4),
        };
      case 'banner_sunset_7d':
        return {
          'icon': Icons.wb_twilight,
          'iconColor': const Color(0xFFFF6F00),
          'gradient': [const Color(0xFFFFE0B2), const Color(0xFFFFCC80)],
          'borderColor': const Color(0xFFFFB74D),
        };
      case 'banner_season_gold':
        return {
          'icon': Icons.emoji_events,
          'iconColor': const Color(0xFFFF8F00),
          'gradient': [const Color(0xFFFFF8E1), const Color(0xFFFFECB3)],
          'borderColor': const Color(0xFFFFD54F),
        };
      case 'banner_season_silver':
        return {
          'icon': Icons.emoji_events,
          'iconColor': const Color(0xFF78909C),
          'gradient': [const Color(0xFFECEFF1), const Color(0xFFCFD8DC)],
          'borderColor': const Color(0xFFB0BEC5),
        };
      case 'banner_season_bronze':
        return {
          'icon': Icons.emoji_events,
          'iconColor': const Color(0xFF8D6E63),
          'gradient': [const Color(0xFFEFEBE9), const Color(0xFFD7CCC8)],
          'borderColor': const Color(0xFFBCAAA4),
        };
      // Titles
      case 'title_sweet':
        return {
          'icon': Icons.cake,
          'iconColor': const Color(0xFFEC407A),
          'gradient': [const Color(0xFFFCE4EC), const Color(0xFFF8BBD0)],
          'borderColor': const Color(0xFFF48FB1),
        };
      case 'title_steady':
        return {
          'icon': Icons.shield,
          'iconColor': const Color(0xFF5C6BC0),
          'gradient': [const Color(0xFFE8EAF6), const Color(0xFFC5CAE9)],
          'borderColor': const Color(0xFF9FA8DA),
        };
      case 'title_flash_30d':
        return {
          'icon': Icons.flash_on,
          'iconColor': const Color(0xFFFFA000),
          'gradient': [const Color(0xFFFFF8E1), const Color(0xFFFFECB3)],
          'borderColor': const Color(0xFFFFD54F),
        };
      // Themes
      case 'theme_cotton':
        return {
          'icon': Icons.cloud,
          'iconColor': const Color(0xFF90A4AE),
          'gradient': [const Color(0xFFF5F5F5), const Color(0xFFE0E0E0)],
          'borderColor': const Color(0xFFBDBDBD),
        };
      case 'theme_sky':
        return {
          'icon': Icons.wb_sunny,
          'iconColor': const Color(0xFF42A5F5),
          'gradient': [const Color(0xFFE3F2FD), const Color(0xFFBBDEFB)],
          'borderColor': const Color(0xFF90CAF9),
        };
      case 'theme_mocha_30d':
        return {
          'icon': Icons.coffee,
          'iconColor': const Color(0xFF6D4C41),
          'gradient': [const Color(0xFFEFEBE9), const Color(0xFFD7CCC8)],
          'borderColor': const Color(0xFFBCAAA4),
        };
      // Utility
      case 'leave_reduce_1':
        return {
          'icon': Icons.healing,
          'iconColor': const Color(0xFF66BB6A),
          'gradient': [const Color(0xFFE8F5E9), const Color(0xFFC8E6C9)],
          'borderColor': const Color(0xFFA5D6A7),
        };
      case 'leave_reduce_3':
        return {
          'icon': Icons.local_hospital,
          'iconColor': const Color(0xFF43A047),
          'gradient': [const Color(0xFFE8F5E9), const Color(0xFFA5D6A7)],
          'borderColor': const Color(0xFF81C784),
        };
    }

    // Fallback by category
    switch (category) {
      case 'banner':
        return {
          'icon': Icons.flag,
          'iconColor': const Color(0xFFB24B5A),
          'gradient': [const Color(0xFFF6C1C9), const Color(0xFFF3E7EA)],
          'borderColor': const Color(0xFFE6DDD8),
        };
      case 'title':
        return {
          'icon': Icons.badge,
          'iconColor': const Color(0xFF6B5CA5),
          'gradient': [const Color(0xFFD9D0F2), const Color(0xFFF1ECFA)],
          'borderColor': const Color(0xFFE6DDD8),
        };
      case 'theme':
        return {
          'icon': Icons.palette,
          'iconColor': const Color(0xFF3A7D5C),
          'gradient': [const Color(0xFFCDEBD8), const Color(0xFFEFF8F2)],
          'borderColor': const Color(0xFFE6DDD8),
        };
      case 'utility':
        return {
          'icon': Icons.handyman,
          'iconColor': const Color(0xFFB46B00),
          'gradient': [const Color(0xFFFFD79E), const Color(0xFFFFF2DF)],
          'borderColor': const Color(0xFFE6DDD8),
        };
      default:
        return {
          'icon': Icons.category,
          'iconColor': const Color(0xFF7A7A7A),
          'gradient': [const Color(0xFFE0E0E0), const Color(0xFFF5F5F5)],
          'borderColor': const Color(0xFFE6DDD8),
        };
    }
  }

  void _maybeShowPurchaseDialog(BuildContext context, GameService game) {
    if (game.lastPurchaseItemKey == null || game.lastPurchaseSuccess != true) {
      return;
    }
    final itemKey = game.lastPurchaseItemKey!;
    final extended = game.lastPurchaseExtended;
    final item = game.shopItems.firstWhere(
      (i) => i['item_key'] == itemKey,
      orElse: () => {},
    );
    game.clearLastPurchaseResult();
    if (item.isEmpty) return;

    final name = item['name']?.toString() ?? '';
    final category = item['category']?.toString() ?? '';
    final isConsumable = category == 'utility' ||
        (item['effect_type']?.toString() ?? '') == 'leave_count_reduce';
    final isBanner = category == 'banner';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(extended ? '기간 연장 완료' : '구매 완료'),
        content: Text(
          extended
              ? '$name 기간이 연장되었어요.'
              : isBanner
                  ? '구매가 완료되었습니다.\n배너가 적용되었습니다.'
                  : '구매가 완료되었습니다.\n바로 장착하시겠어요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기'),
          ),
          if (!extended && !isConsumable && !isBanner)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                game.equipItem(itemKey);
              },
              child: const Text('장착하기'),
            ),
        ],
      ),
    );

    if (!extended && isBanner) {
      game.equipItem(itemKey);
    }
  }

  void _showItemDetailDialog(BuildContext context, Map<String, dynamic> item) {
    final name = item['name']?.toString() ?? '';
    final price = item['price'] ?? 0;
    final isSeason = item['is_season'] == true;
    final isPermanent = item['is_permanent'] == true;
    final durationDays = item['duration_days'];
    final category = item['category']?.toString() ?? '';
    final effectType = item['effect_type']?.toString() ?? '';
    final effectValue = item['effect_value'];

    final info = <String>[
      _categoryLabel(category),
      isSeason ? '시즌 아이템' : '일반 아이템',
      isPermanent ? '영구' : '기간제 ${durationDays ?? '-'}일',
    ];
    if (effectType == 'leave_count_reduce') {
      info.add('효과: 탈주 -${effectValue ?? 1}');
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildItemThumbnail(category, name, isSeason, item['item_key']?.toString()),
            const SizedBox(height: 12),
            ...info.map(
              (t) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline,
                        size: 16, color: Color(0xFF9A8E8A)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        t,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF6A5A52)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$price 골드',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Color(0xFF4A4080),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  String _categoryLabel(String category) {
    switch (category) {
      case 'banner':
        return '배너';
      case 'title':
        return '칭호';
      case 'theme':
        return '테마/카드 스킨';
      case 'utility':
        return '유틸리티';
      default:
        return '아이템';
    }
  }

  Widget _buildCategoryTabs(List<String> labels) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(14),
      ),
      child: TabBar(
        isScrollable: true,
        labelColor: const Color(0xFF5A4038),
        unselectedLabelColor: const Color(0xFF9A8E8A),
        indicatorColor: const Color(0xFFB9A8A1),
        tabs: labels.map((t) => Tab(text: t)).toList(),
      ),
    );
  }

  List<Map<String, dynamic>> _filterShop(
    List<Map<String, dynamic>> items,
    String category,
  ) {
    if (category == 'all') return items;
    return items.where((i) => (i['category']?.toString() ?? '') == category).toList();
  }

  List<Map<String, dynamic>> _filterInventory(
    List<Map<String, dynamic>> items,
    String category,
  ) {
    if (category == 'all') return items;
    if (category == 'season') {
      return items.where((i) => i['is_season'] == true).toList();
    }
    return items.where((i) => (i['category']?.toString() ?? '') == category).toList();
  }

  String _buildItemTag(bool isSeason, bool isPermanent, dynamic durationDays) {
    if (isSeason) {
      return '시즌 아이템';
    }
    if (isPermanent) {
      return '영구';
    }
    if (durationDays != null) {
      return '기간제 ${durationDays}일';
    }
    return '기간제';
  }

  String _formatExpire(dynamic value) {
    try {
      final dt = DateTime.parse(value.toString()).toLocal();
      return '만료: ${dt.year}.${dt.month}.${dt.day}';
    } catch (_) {
      return '만료 예정';
    }
  }
}
