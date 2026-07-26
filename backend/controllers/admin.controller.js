const User = require("../models/user.model");
const Transaction = require("../models/transaction.model");

exports.getAdminDashboard = async (req, res) => {
  try {
    const [
      totalUsers,
      activeUsers,
      suspendedUsers,
      blockedUsers,
      totalCustomers,
      totalAgents,
      totalStateManagers,
      totalZonalManagers,
      totalTransactions,
    ] = await Promise.all([
      User.countDocuments(),
      User.countDocuments({ status: "ACTIVE" }),
      User.countDocuments({ status: "SUSPENDED" }),
      User.countDocuments({ status: "BLOCKED" }),
      User.countDocuments({ role: "CUSTOMER" }),
      User.countDocuments({ role: "AGENT" }),
      User.countDocuments({ role: "STATE_MANAGER" }),
      User.countDocuments({ role: "ZONAL_MANAGER" }),
      Transaction.countDocuments(),
    ]);

    return res.status(200).json({
      success: true,
      data: {
        totalUsers,
        activeUsers,
        suspendedUsers,
        blockedUsers,
        totalCustomers,
        totalAgents,
        totalStateManagers,
        totalZonalManagers,
        totalTransactions,
      },
    });
  } catch (error) {
    console.error("Admin dashboard error:", error);

    return res.status(500).json({
      success: false,
      message: "Failed to load admin dashboard.",
      error: error.message,
    });
  }
};