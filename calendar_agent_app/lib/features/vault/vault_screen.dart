import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../../services/memory_service.dart';
import 'dart:ui';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';

class VaultScreen extends StatefulWidget {
  final String userId;
  final bool isDark;
  final VoidCallback onClose;

  const VaultScreen({
    super.key,
    required this.userId,
    required this.isDark,
    required this.onClose,
  });

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  List<Map<String, dynamic>> _memories = [];
  List<Map<String, dynamic>> _filteredMemories = [];
  bool _isLoading = true;
  String _selectedCategory = 'ALL';
  final List<String> _categories = ['ALL', 'PERSONAL', 'TASK', 'EVENT', 'SYSTEM'];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadMemories();
  }

  Future<void> _loadMemories() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final data = await MemoryService.getAllMemories(widget.userId);
      if (mounted) {
        setState(() {
          _memories = data;
          _applyFilters(_searchController.text);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilters(String query) {
    setState(() {
      _filteredMemories = _memories.where((m) {
        final text = (m['content'] ?? m['text'] ?? '').toString().toLowerCase();
        final source = (m['source_type'] ?? 'Personal').toString().toUpperCase();
        
        bool matchesSearch = query.isEmpty || text.contains(query.toLowerCase());
        bool matchesCategory = _selectedCategory == 'ALL' || source == _selectedCategory;
        
        return matchesSearch && matchesCategory;
      }).toList();
    });
  }

  Future<void> _delete(int id) async {
    await MemoryService.deleteMemory(id);
    _loadMemories();
  }

  Map<String, List<Map<String, dynamic>>> _getGroupedMemories() {
    final Map<String, List<Map<String, dynamic>>> groups = {};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    for (var memory in _filteredMemories) {
      final dateStr = memory['created_at'];
      if (dateStr == null) {
        groups.putIfAbsent('ARCHIVED', () => []).add(memory);
        continue;
      }

      final date = DateTime.parse(dateStr);
      final compareDate = DateTime(date.year, date.month, date.day);

      String groupKey;
      if (compareDate == today) {
        groupKey = 'ACTIVE TODAY';
      } else if (compareDate == yesterday) {
        groupKey = 'YESTERDAY';
      } else if (now.difference(date).inDays < 7) {
        groupKey = 'RECENT SYNC';
      } else {
        groupKey = DateFormat('MMMM yyyy').format(date).toUpperCase();
      }

      groups.putIfAbsent(groupKey, () => []).add(memory);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = theme.colorScheme.primary;
    final groupedMemories = _getGroupedMemories();

    return Column(
      children: [
        _buildHeader(theme, accentColor),
        Expanded(
          child: _isLoading
              ? _buildLoadingState(accentColor)
              : _filteredMemories.isEmpty
                  ? _buildEmptyState(theme, accentColor)
                  : _buildMemoryList(groupedMemories, theme, accentColor),
        ),
      ],
    );
  }

  Widget _buildHeader(ThemeData theme, Color accentColor) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: accentColor.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'NEURAL REPOSITORY',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4,
                      color: accentColor,
                    ),
                  ).animate().fadeIn(duration: 600.ms).slideX(begin: -0.2),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accentColor,
                          boxShadow: [
                            BoxShadow(
                              color: accentColor.withValues(alpha: 0.5),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'CORE SYNAPSE ACTIVE',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              _buildStatsBadge(theme, accentColor),
            ],
          ),
          const SizedBox(height: 24),
          _buildSearchField(theme, accentColor),
          const SizedBox(height: 16),
          _buildCategoryBar(theme, accentColor),
        ],
      ),
    );
  }

  Widget _buildStatsBadge(ThemeData theme, Color accentColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Text(
            _filteredMemories.length.toString().padLeft(2, '0'),
            style: GoogleFonts.jetBrainsMono(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: accentColor,
            ),
          ),
          Text(
            'NODES',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 7,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(ThemeData theme, Color accentColor) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: widget.isDark 
                ? Colors.white.withValues(alpha: 0.05) 
                : Colors.black.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.1),
              width: 1,
            ),
          ),
          child: TextField(
            controller: _searchController,
            onChanged: _applyFilters,
            style: GoogleFonts.manrope(
              fontSize: 13,
              color: theme.colorScheme.onSurface,
            ),
            decoration: InputDecoration(
              hintText: 'QUERY NEURAL PATHWAYS...',
              hintStyle: GoogleFonts.spaceGrotesk(
                fontSize: 9,
                letterSpacing: 2,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
              ),
              prefixIcon: Icon(Icons.search_rounded, size: 18, color: accentColor),
              suffixIcon: _searchController.text.isNotEmpty 
                ? IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () {
                      _searchController.clear();
                      _applyFilters('');
                    },
                  )
                : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryBar(ThemeData theme, Color accentColor) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _categories.map((cat) {
          final isActive = _selectedCategory == cat;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedCategory = cat;
                  _applyFilters(_searchController.text);
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isActive ? accentColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isActive ? accentColor : accentColor.withValues(alpha: 0.1),
                    width: 1,
                  ),
                ),
                child: Text(
                  cat,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                    color: isActive ? Colors.white : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMemoryList(Map<String, List<Map<String, dynamic>>> groups, ThemeData theme, Color accentColor) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: groups.length,
      itemBuilder: (context, groupIndex) {
        final groupKey = groups.keys.elementAt(groupIndex);
        final memories = groups[groupKey]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 32, bottom: 16, left: 4),
              child: Row(
                children: [
                  Container(
                    width: 2,
                    height: 12,
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    groupKey,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                    ),
                  ),
                ],
              ),
            ),
            MasonryGridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: memories.length,
              itemBuilder: (context, index) {
                return _VaultBentoCard(
                  memory: memories[index],
                  isDark: widget.isDark,
                  onDelete: () => _delete(memories[index]['id']),
                )
                .animate()
                .fadeIn(delay: (index * 50).ms, duration: 400.ms)
                .slideY(begin: 0.1, curve: Curves.easeOutCubic);
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildLoadingState(Color accentColor) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(accentColor),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'RECALLING NEURAL PATHS...',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 9,
              letterSpacing: 2,
              fontWeight: FontWeight.w900,
              color: accentColor.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, Color accentColor) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.memory_rounded,
            size: 48,
            color: accentColor.withValues(alpha: 0.05),
          ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 2.seconds),
          const SizedBox(height: 24),
          Text(
            'NEURAL VOID DETECTED',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 11,
              letterSpacing: 3,
              fontWeight: FontWeight.w900,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'No memories found in this sector.',
            style: TextStyle(
              fontSize: 10,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.15),
            ),
          ),
        ],
      ),
    );
  }
}

class _VaultBentoCard extends StatelessWidget {
  final Map<String, dynamic> memory;
  final bool isDark;
  final VoidCallback onDelete;

  const _VaultBentoCard({
    required this.memory,
    required this.isDark,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = theme.colorScheme.primary;
    final text = (memory['content'] ?? memory['text'] ?? '').toString();
    final source = (memory['source_type'] ?? 'Personal').toString().toUpperCase();
    final date = memory['created_at'] != null 
        ? DateFormat('MMM dd').format(DateTime.parse(memory['created_at']))
        : '??';

    return Container(
      decoration: BoxDecoration(
        color: isDark 
            ? Colors.white.withValues(alpha: 0.02) 
            : Colors.black.withValues(alpha: 0.015),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildSourceTag(source, accentColor),
                    Text(
                      date,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 7,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  text,
                  style: GoogleFonts.manrope(
                    fontSize: 11.5,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                  ),
                  maxLines: 10,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 4,
            right: 4,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: onDelete,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: theme.colorScheme.error.withValues(alpha: 0.2),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceTag(String label, Color accentColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: GoogleFonts.spaceGrotesk(
          fontSize: 7,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
          color: accentColor,
        ),
      ),
    );
  }
}
