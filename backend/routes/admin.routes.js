const express = require("express");

const {
  getAdminDashboard,
  getAdminTransactions,
  getAdminDeliveries,
  updateDeliveryStatus,
  getAdminUsers,
  createAdminUser,
  updateAdminUserStatus,
} = require("../controllers/admin.controller");

const {
  protect,
  adminOnly,
} = require("../middleware/auth.middleware");

const router = express.Router();

const MANAGEMENT_ROLES = [
  "HEAD_OFFICE",
  "ZONAL_MANAGER",
  "STATE_MANAGER",
];

/*
 * Management dashboard.
 *
 * Important: getAdminDashboard should eventually
 * return records limited to the logged-in manager's
 * zone/state.
 */
router.get(
  "/dashboard",
  protect,
  adminOnly(...MANAGEMENT_ROLES),
  getAdminDashboard
);

/*
 * User management.
 */
router.get(
  "/users",
  protect,
  adminOnly(...MANAGEMENT_ROLES),
  getAdminUsers
);

router.post(
  "/users",
  protect,
  adminOnly(...MANAGEMENT_ROLES),
  createAdminUser
);

router.patch(
  "/users/:id/status",
  protect,
  adminOnly(...MANAGEMENT_ROLES),
  updateAdminUserStatus
);

/*
 * Head Office-only financial and operational routes.
 */
router.get(
  "/transactions",
  protect,
  adminOnly("HEAD_OFFICE"),
  getAdminTransactions
);

router.get(
  "/deliveries",
  protect,
  adminOnly("HEAD_OFFICE"),
  getAdminDeliveries
);

router.patch(
  "/deliveries/:id/status",
  protect,
  adminOnly("HEAD_OFFICE"),
  updateDeliveryStatus
);

module.exports = router;