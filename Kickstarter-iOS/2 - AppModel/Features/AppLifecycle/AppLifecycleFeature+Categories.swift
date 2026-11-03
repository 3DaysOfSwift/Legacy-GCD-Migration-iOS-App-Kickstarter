import KsApi

func deepLinkCategories(rawParams: [String: String]) -> (Param?, Param?) {
  let parentCategoryParams = rawParams["parent_category_id"]
  let subCategoryParams = rawParams["category_id"]
  var categoryParam: Param?
  var subcategoryParam: Param?

  let rawId: (String?) -> Int? = { rawParam in
    guard let rawParamValue = rawParam else {
      return .none
    }

    return Int(rawParamValue)
  }

  let rawName: (String?) -> String? = { rawParam in
    guard let rawParamValue = rawParam else {
      return .none
    }

    return String(rawParamValue)
  }

  if let categoryId = rawId(parentCategoryParams) {
    categoryParam = Param.id(categoryId)
  } else if let categoryName = rawName(parentCategoryParams) {
    categoryParam = Param.slug(categoryName)
  }

  if let subcategoryId = rawId(subCategoryParams) {
    subcategoryParam = Param.id(subcategoryId)
  } else if let subcategoryName = rawName(subCategoryParams) {
    subcategoryParam = Param.slug(subcategoryName)
  }

  let subCategoryWithNoParentCategory = categoryParam == nil && subcategoryParam != nil

  categoryParam = subCategoryWithNoParentCategory ? subcategoryParam : categoryParam
  subcategoryParam = subCategoryWithNoParentCategory ? nil : subcategoryParam

  return (categoryParam, subcategoryParam)
}

/// Will check id and name of category and subcategory against all available categories and subcategories inside envelope
func findCategoryFromRootCategories(
  envelope: RootCategoriesEnvelope,
  categoryParam: Param,
  subcategoryParam: Param?
) -> KsApi.Category? {
  let allRootCategoryIdsAndNames = envelope.rootCategories.compactMap { $0 }

  let allSubcategoryIdsAndNames = envelope.rootCategories.compactMap { $0.subcategories?.nodes }
    .flatMap { $0 }

  let allCategoryIdsAndNames = allRootCategoryIdsAndNames + allSubcategoryIdsAndNames

  let routableCategory = allCategoryIdsAndNames.first(where: { category in
    category.intID == categoryParam.id
      || category.name.lowercased() == categoryParam.slug?.lowercased()
  })

  let routableSubcategory =
    routableCategory != nil
    ? allCategoryIdsAndNames.first(where: { category in
      category.intID == subcategoryParam?.id
        || category.name.lowercased()
          == subcategoryParam?.slug?
          .lowercased()
    }) : nil

  return routableSubcategory ?? routableCategory
}
