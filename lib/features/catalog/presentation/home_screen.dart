import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../app_config/domain/app_config.dart';
import '../../app_config/domain/home_layout.dart';
import '../../app_config/presentation/app_config_controller.dart';
import '../../cart/presentation/cart_badge_button.dart';
import '../../dev_tools/dev_tools_screen.dart';
import '../../orders/presentation/orders_screen.dart';
import '../../search/search_screen.dart';
import '../data/catalog_repository.dart';
import '../domain/product.dart';
import 'catalog_controller.dart';
import 'category_screen.dart';
import 'widgets/product_card.dart';

final homeDealsProvider = FutureProvider<CatalogPage>(
  (ref) => ref.watch(catalogRepositoryProvider).getDeals(limit: 10),
);

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      ref
          .read(catalogControllerProvider(kAllProductsCategory).notifier)
          .loadMore();
    }
  }

  Future<void> _refresh() async {
    await ref
        .read(catalogControllerProvider(kAllProductsCategory).notifier)
        .refresh();
    ref
      ..invalidate(categoriesProvider)
      ..invalidate(homeDealsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final server = ref.watch(mockServerProvider);
    final config = ref.watch(appConfigControllerProvider);
    final catalog = ref.watch(catalogControllerProvider(kAllProductsCategory));
    final sections = HomeLayout.parse(config.homeSectionsJson);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(server.storeName,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const Text('Delivery in 10 minutes ⚡',
                style: TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Dev tools',
            icon: const Icon(Icons.bug_report_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const DevToolsScreen()),
            ),
          ),
          IconButton(
            tooltip: 'My orders',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const OrdersScreen()),
            ),
          ),
          const CartBadgeButton(),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            const SliverToBoxAdapter(child: _SearchEntry()),
            if (!config.storeOpen)
              SliverToBoxAdapter(
                child: _StoreClosedBanner(message: config.storeClosedMessage),
              ),
            for (final section in sections)
              switch (section) {
                HomeSection.banner => config.homeBanner == null
                    ? const SliverToBoxAdapter(child: SizedBox.shrink())
                    : SliverToBoxAdapter(
                        key: const ValueKey('home-section-banner'),
                        child: _HomeBanner(banner: config.homeBanner!),
                      ),
                HomeSection.categories => const SliverToBoxAdapter(
                    key: ValueKey('home-section-categories'),
                    child: _CategoriesRow(),
                  ),
                HomeSection.deals => const _DealsSection(
                    key: ValueKey('home-section-deals'),
                  ),
                HomeSection.allProducts => _AllProductsSection(
                    key: const ValueKey('home-section-allProducts'),
                    state: catalog,
                  ),
              },
          ],
        ),
      ),
    );
  }
}

class _SearchEntry extends StatelessWidget {
  const _SearchEntry();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
          ),
          child: InputDecorator(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search for products',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Search "milk", "chips"…',
                style: TextStyle(color: Colors.grey)),
          ),
        ),
      );
}

class _StoreClosedBanner extends StatelessWidget {
  const _StoreClosedBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: Colors.orange.shade100,
        padding: const EdgeInsets.all(12),
        child: Text(
          message.isEmpty ? 'The store is closed right now.' : message,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      );
}

class _HomeBanner extends StatelessWidget {
  const _HomeBanner({required this.banner});

  final HomeBanner banner;

  @override
  Widget build(BuildContext context) {
    final color = _bannerColor(banner.colorHex);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(banner.title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
          if (banner.subtitle.isNotEmpty)
            Text(banner.subtitle, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }

  Color _bannerColor(String hex) {
    final value = hex.replaceFirst('#', '');
    final parsed = int.tryParse(value, radix: 16);
    if (parsed == null) return const Color(0xFFFF6F00);
    return Color(value.length == 8 ? parsed : 0xFF000000 | parsed);
  }
}

class _CategoriesRow extends ConsumerWidget {
  const _CategoriesRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);
    return SizedBox(
      height: 104,
      child: categories.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(categoriesProvider),
            child: const Text("Couldn't load categories. Retry"),
          ),
        ),
        data: (items) => ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            final category = items[index];
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CategoryScreen(category: category),
                ),
              ),
              child: SizedBox(
                width: 76,
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: Colors.green.shade50,
                      child: Text(category.emoji,
                          style: const TextStyle(fontSize: 24)),
                    ),
                    const SizedBox(height: 4),
                    Text(category.name,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DealsSection extends ConsumerWidget {
  const _DealsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deals = ref.watch(homeDealsProvider);
    return deals.when(
      loading: () => const SliverToBoxAdapter(
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
      data: (page) => page.items.isEmpty
          ? const SliverToBoxAdapter(child: SizedBox.shrink())
          : SliverMainAxisGroup(
              slivers: [
                const SliverToBoxAdapter(
                  child: _SectionHeading(title: 'Deals'),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 290,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: page.items.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, index) => SizedBox(
                        width: 170,
                        child: ProductCard(product: page.items[index]),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _AllProductsSection extends StatelessWidget {
  const _AllProductsSection({super.key, required this.state});

  final CatalogState state;

  @override
  Widget build(BuildContext context) => SliverMainAxisGroup(
        slivers: [
          const SliverToBoxAdapter(
            child: _SectionHeading(title: 'All products'),
          ),
          if (state.fromCache)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text('You are offline. Showing saved products.'),
              ),
            ),
          if (state.isLoadingFirstPage)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (state.items.isEmpty && state.errorMessage != null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text(state.errorMessage!)),
            )
          else if (state.items.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('No products here yet')),
            )
          else ...[
            SliverPadding(
              padding: const EdgeInsets.all(12),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.62,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => ProductCard(product: state.items[index]),
                  childCount: state.items.length,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Center(
                  child: state.isLoadingMore
                      ? const CircularProgressIndicator()
                      : state.errorMessage != null
                          ? const Text("Couldn't load more products.")
                          : !state.hasMore
                              ? const Text("You've seen it all 🎉")
                              : const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        ],
      );
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      );
}
