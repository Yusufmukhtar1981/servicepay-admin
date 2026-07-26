const User = require("../models/user.model");
const Transaction = require("../models/transaction.model");

const getAdminDashboard = async (req, res) => {
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
      kycVerifiedUsers,
      pendingKycUsers,
      walletSummary,
      commissionSummary,
      transactionSummary,
      successfulTransactions,
      pendingTransactions,
      failedTransactions,
      recentUsers,
      recentTransactions,
    ] = await Promise.all([
      User.countDocuments(),

      User.countDocuments({ status: "ACTIVE" }),

      User.countDocuments({ status: "SUSPENDED" }),

      User.countDocuments({ status: "BLOCKED" }),

      User.countDocuments({ role: "CUSTOMER" }),

      User.countDocuments({ role: "AGENT" }),

      User.countDocuments({ role: "STATE_MANAGER" }),

      User.countDocuments({ role: "ZONAL_MANAGER" }),

      User.countDocuments({ kycVerified: true }),

      User.countDocuments({
        role: "CUSTOMER",
        kycVerified: false,
      }),

      User.aggregate([
        {
          $group: {
            _id: null,
            totalWalletBalance: {
              $sum: "$walletBalance",
            },
          },
        },
      ]),

      User.aggregate([
        {
          $group: {
            _id: null,
            totalCommissionBalance: {
              $sum: "$commissionBalance",
            },
            totalEarnings: {
              $sum: "$totalEarnings",
            },
          },
        },
      ]),

      Transaction.aggregate([
        {
          $group: {
            _id: null,
            totalTransactions: {
              $sum: 1,
            },
            totalTransactionValue: {
              $sum: "$amount",
            },
            totalServicepayProfit: {
              $sum: "$servicepayProfit",
            },
          },
        },
      ]),

      Transaction.countDocuments({
        status: "SUCCESSFUL",
      }),

      Transaction.countDocuments({
        status: "PENDING",
      }),

      Transaction.countDocuments({
        status: "FAILED",
      }),

      User.find()
        .select(
          "fullName phone email role status walletBalance kycVerified createdAt"
        )
        .sort({ createdAt: -1 })
        .limit(5)
        .lean(),

      Transaction.find()
        .populate("customerId", "fullName phone email")
        .select(
          "reference customerId serviceType provider amount status createdAt"
        )
        .sort({ createdAt: -1 })
        .limit(5)
        .lean(),
    ]);

    const walletData = walletSummary[0] || {};
    const commissionData = commissionSummary[0] || {};
    const transactionData = transactionSummary[0] || {};

    return res.status(200).json({
      success: true,
      message: "Admin dashboard loaded successfully.",
      data: {
        users: {
          total: totalUsers,
          active: activeUsers,
          suspended: suspendedUsers,
          blocked: blockedUsers,
          customers: totalCustomers,
          agents: totalAgents,
          stateManagers: totalStateManagers,
          zonalManagers: totalZonalManagers,
        },

        kyc: {
          verified: kycVerifiedUsers,
          pending: pendingKycUsers,
        },

        wallets: {
          totalBalance:
            walletData.totalWalletBalance || 0,
          totalCommissionBalance:
            commissionData.totalCommissionBalance || 0,
          totalEarnings:
            commissionData.totalEarnings || 0,
        },

        transactions: {
          total:
            transactionData.totalTransactions || 0,
          totalValue:
            transactionData.totalTransactionValue || 0,
          successful: successfulTransactions,
          pending: pendingTransactions,
          failed: failedTransactions,
          servicepayProfit:
            transactionData.totalServicepayProfit || 0,
        },

        recentUsers,
        recentTransactions,
      },
    });
  } catch (error) {
    console.error("Admin dashboard error:", error);

    return res.status(500).json({
      success: false,
      message: "Unable to load admin dashboard.",
      error:
        process.env.NODE_ENV === "development"
          ? error.message
          : undefined,
    });
  }
};

module.exports = {
  getAdminDashboard,
};