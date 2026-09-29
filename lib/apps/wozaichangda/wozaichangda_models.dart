class WozaichangdaCategory {
  final String name;
  final List<WozaichangdaApp> apps;

  const WozaichangdaCategory({required this.name, required this.apps});
}

class WozaichangdaApp {
  final String name;
  final String icon;
  final String page;
  final String path;
  final String id;
  final String appType;

  const WozaichangdaApp({
    required this.name,
    required this.icon,
    required this.page,
    required this.path,
    required this.id,
    required this.appType,
  });
}
