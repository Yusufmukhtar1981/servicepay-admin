const express = require("express");

const {
  getAdminDashboard,
  getAdminTransactions,
} = require("../controllers/admin.controller");

const {
  protect,
  adminOnly,
} = require("../middleware/auth.middleware");

const router = express.Router();

router.get(
  "/dashboard",
  protect,
  adminOnly("HEAD_OFFICE"),
  getAdminDashboard
);

router.get(
  "/transactions",
  protect,
  adminOnly("HEAD_OFFICE"),
  getAdminTransactions
);

module.exports = router;