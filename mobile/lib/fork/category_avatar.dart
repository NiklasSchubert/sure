import 'package:flutter/material.dart';

import '../models/category.dart' as models;
import '../widgets/sure_icon.dart';

class CategoryAvatar extends StatelessWidget {
  static const _fallbackIcon = 'shapes';

  final models.Category? category;
  final double size;

  const CategoryAvatar({super.key, required this.category, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final categoryColor = parseHexColor(category?.color) ?? colorScheme.outline;
    final iconName = _bundledIcons.lookup(category?.icon) ?? _fallbackIcon;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: categoryColor.withValues(alpha: 0.18),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: SureIcon(iconName, size: size * 0.5, color: categoryColor),
      ),
    );
  }
}

Color? parseHexColor(String? hex) {
  if (hex == null) return null;

  final digits = hex.replaceFirst('#', '');
  final isRgb = digits.length == 6;
  if (!isRgb) return null;

  final rgb = int.tryParse(digits, radix: 16);
  if (rgb == null) return null;

  return Color(0xFF000000 | rgb);
}

// Every SVG in assets/icons/lucide; a name outside it would fail to load
const _bundledIcons = {
  'ambulance', 'apple', 'award', 'baby', 'badge-dollar-sign',
  'banknote', 'bar-chart-3', 'barcode', 'bath', 'battery', 'bed-single',
  'beer', 'bike', 'bitcoin', 'bluetooth', 'bone', 'book', 'book-open',
  'briefcase', 'building', 'bus', 'cake', 'calculator',
  'calendar-heart', 'calendar-range', 'camera', 'car', 'cat',
  'chart-line', 'chevron-down', 'chevron-right', 'chevron-up',
  'circle-alert', 'circle-check', 'circle-dollar-sign',
  'circle-parking', 'cloud-check', 'coffee', 'coins', 'compass',
  'cookie', 'cooking-pot', 'credit-card', 'dices', 'dog', 'drama',
  'drill', 'droplet', 'drum', 'dumbbell', 'film', 'flame', 'flower',
  'flower-2', 'fuel', 'gamepad-2', 'gem', 'gift', 'glasses', 'globe',
  'graduation-cap', 'hammer', 'hand-coins', 'hand-heart',
  'hand-helping', 'handshake', 'headphones', 'heart', 'heart-handshake',
  'heart-pulse', 'home', 'hotel', 'house', 'ice-cream-cone', 'key',
  'landmark', 'laptop', 'leaf', 'lightbulb', 'luggage', 'mail',
  'map-pin', 'martini', 'mic', 'monitor', 'moon', 'music', 'package',
  'palette', 'party-popper', 'paw-print', 'pen', 'pencil', 'percent',
  'phone', 'pie-chart', 'piggy-bank', 'pill', 'pizza', 'plane', 'plug',
  'popcorn', 'power', 'printer', 'puzzle', 'receipt', 'receipt-text',
  'refresh-cw', 'ribbon', 'scale', 'scissors', 'settings', 'shapes',
  'shield', 'shield-plus', 'shirt', 'shopping-bag', 'shopping-basket',
  'shopping-cart', 'smartphone', 'sparkles', 'sprout', 'stethoscope',
  'store', 'sun', 'tablet-smartphone', 'tag', 'target', 'tent',
  'thermometer', 'ticket', 'train', 'tree-palm', 'trees',
  'trending-down', 'trending-up', 'trophy', 'truck', 'tv', 'umbrella',
  'undo-2', 'unplug', 'users', 'utensils', 'video', 'wallet',
  'wallet-cards', 'waves', 'wifi', 'wine', 'wrench', 'zap',
};
