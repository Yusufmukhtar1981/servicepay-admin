import 'admin_permissions.dart';

// Ordinary Head Office reporting retains established full-role visibility.
// Mutation requires the named permission, not merely a wildcard.
bool canViewHeadOfficePerformance(AdminAccess access) =>
    access.isHeadOffice && access.has(AdminPermissions.usersView);

bool canManageHeadOfficeHierarchy(AdminAccess access) =>
    access.isHeadOffice &&
    access.permissions.any((value) =>
        value.trim().toLowerCase() == AdminPermissions.hierarchyManage);

// Head Office uses an eager IndexedStack. Do not fetch team reports or the
// customer directory just because these new destinations exist in its menu.
bool shouldBuildHeadOfficeManagementPage(
        String label, int index, int selectedIndex) =>
    !const {'Management Performance', 'Customer Assignments'}.contains(label) ||
    index == selectedIndex;
