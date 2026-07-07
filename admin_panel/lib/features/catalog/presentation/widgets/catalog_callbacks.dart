import '../../../categories/domain/models/category.dart';
import '../../../sub_categories/domain/models/sub_category.dart';
import '../../../services/domain/models/service.dart';

/// Bundles all CRUD + toggle callbacks for the Catalog widget tree.
/// Defined once in CatalogPage and passed down; each widget calls only
/// the callbacks it needs.
class CatalogCallbacks {
  const CatalogCallbacks({
    required this.onEditCategory,
    required this.onDeleteCategory,
    required this.onToggleCategoryActive,
    required this.onAddSubCategory,
    required this.onEditSubCategory,
    required this.onDeleteSubCategory,
    required this.onToggleSubCategoryActive,
    required this.onAddService,
    required this.onEditService,
    required this.onDeleteService,
    required this.onToggleServiceActive,
    required this.onOpenAttributes,
  });

  final void Function(Category) onEditCategory;
  final void Function(Category) onDeleteCategory;
  final void Function(Category, bool) onToggleCategoryActive;
  final void Function(Category) onAddSubCategory;

  final void Function(SubCategory) onEditSubCategory;
  final void Function(SubCategory) onDeleteSubCategory;
  final void Function(SubCategory, bool) onToggleSubCategoryActive;
  final void Function(SubCategory) onAddService;

  final void Function(Service) onEditService;
  final void Function(Service) onDeleteService;
  final void Function(Service, bool) onToggleServiceActive;
  final void Function(Service) onOpenAttributes;
}
