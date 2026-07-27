const mongoose = require("mongoose");

const User = require("../models/user.model");
const Transaction = require("../models/transaction.model");

const toPositiveInteger = (
  value,
  fallback,
  maximum = 100
) => {
  const parsed = Number.parseInt(value, 10);

  if (!Number.isFinite(parsed) || parsed < 1) {
    return fallback;
  }

  return Math.min(parsed, maximum);
};

const escapeRegex = (value = "") => {
  return String(value).replace(
    /[.*+?^${}()|[\]\\]/g,
    "\\$&"
  );
};

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
      successfulTransactions,
      pendingTransactions,
      failedTransactions,
      recentUsers,
      recentTransactions,
      transactionSummary,
      walletSummary,
    ] = await Promise.all([
      User.countDocuments(),

      User.countDocuments({
        status: "ACTIVE",
      }),

      User.countDocuments({
        status: "SUSPENDED",
      }),

      User.countDocuments({
        status: "BLOCKED",
      }),

      User.countDocuments({
        role: "CUSTOMER",
      }),

      User.countDocuments({
        role: "AGENT",
      }),

      User.countDocuments({
        role: "STATE_MANAGER",
      }),

      User.countDocuments({
        role: "ZONAL_MANAGER",
      }),

      Transaction.countDocuments(),

      Transaction.countDocuments({
        status: {
          $in: [
            "SUCCESS",
            "SUCCESSFUL",
            "COMPLETED",
            "APPROVED",
          ],
        },
      }),

      Transaction.countDocuments({
        status: {
          $in: [
            "PENDING",
            "PROCESSING",
          ],
        },
      }),

      Transaction.countDocuments({
        status: {
          $in: [
            "FAILED",
            "CANCELLED",
            "REJECTED",
          ],
        },
      }),

      User.find()
        .select(
          "fullName name email phone role status createdAt"
        )
        .sort({
          createdAt: -1,
        })
        .limit(5)
        .lean(),

      Transaction.find()
        .populate(
          "customerId",
          "fullName name email phone"
        )
        .populate(
          "userId",
          "fullName name email phone"
        )
        .sort({
          createdAt: -1,
        })
        .limit(5)
        .lean(),

      Transaction.aggregate([
        {
          $group: {
            _id: null,

            totalVolume: {
              $sum: {
                $convert: {
                  input: "$amount",
                  to: "double",
                  onError: 0,
                  onNull: 0,
                },
              },
            },

            totalProfit: {
              $sum: {
                $convert: {
                  input: {
                    $ifNull: [
                      "$servicepayProfit",
                      {
                        $ifNull: [
                          "$profit",
                          0,
                        ],
                      },
                    ],
                  },
                  to: "double",
                  onError: 0,
                  onNull: 0,
                },
              },
            },
          },
        },
      ]),

      User.aggregate([
        {
          $group: {
            _id: null,

            totalWalletBalance: {
              $sum: {
                $convert: {
                  input: "$walletBalance",
                  to: "double",
                  onError: 0,
                  onNull: 0,
                },
              },
            },
          },
        },
      ]),
    ]);

    const totalVolume =
      transactionSummary[0]?.totalVolume ?? 0;

    const servicepayProfit =
      transactionSummary[0]?.totalProfit ?? 0;

    const totalWalletBalance =
      walletSummary[0]?.totalWalletBalance ?? 0;

    return res.status(200).json({
      success: true,
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
          pending: 0,
        },

        wallets: {
          totalWalletBalance,
          totalBalance: totalWalletBalance,
        },

        transactions: {
          total: totalTransactions,
          totalVolume,
          totalValue: totalVolume,
          successful: successfulTransactions,
          pending: pendingTransactions,
          failed: failedTransactions,
          servicepayProfit,
        },

        servicepay: {
          totalProfit: servicepayProfit,
        },

        recentUsers,
        recentTransactions,
      },
    });
  } catch (error) {
    console.error(
      "Admin dashboard error:",
      error
    );

    return res.status(500).json({
      success: false,
      message:
        "Failed to load admin dashboard.",
      error: error.message,
    });
  }
};

exports.getAdminTransactions = async (
  req,
  res
) => {
  try {
    const page = toPositiveInteger(
      req.query.page,
      1,
      100000
    );

    const limit = toPositiveInteger(
      req.query.limit,
      20,
      100
    );

    const skip = (page - 1) * limit;

    const search = String(
      req.query.search ?? ""
    ).trim();

    const status = String(
      req.query.status ?? ""
    )
      .trim()
      .toUpperCase();

    const serviceType = String(
      req.query.serviceType ??
        req.query.service ??
        ""
    )
      .trim()
      .toUpperCase();

    const filter = {};

    if (
      status &&
      status !== "ALL"
    ) {
      if (status === "SUCCESSFUL") {
        filter.status = {
          $in: [
            "SUCCESS",
            "SUCCESSFUL",
            "COMPLETED",
            "APPROVED",
          ],
        };
      } else if (status === "FAILED") {
        filter.status = {
          $in: [
            "FAILED",
            "CANCELLED",
            "REJECTED",
          ],
        };
      } else if (status === "PENDING") {
        filter.status = {
          $in: [
            "PENDING",
            "PROCESSING",
          ],
        };
      } else if (status === "REVERSED") {
        filter.status = {
          $in: [
            "REVERSED",
            "REFUNDED",
          ],
        };
      } else {
        filter.status = status;
      }
    }

    if (
      serviceType &&
      serviceType !== "ALL"
    ) {
      filter.serviceType = serviceType;
    }

    if (search) {
      const safeSearch = escapeRegex(search);

      const searchRegex = new RegExp(
        safeSearch,
        "i"
      );

      const userFilter = {
        $or: [
          {
            fullName: searchRegex,
          },
          {
            name: searchRegex,
          },
          {
            phone: searchRegex,
          },
          {
            email: searchRegex,
          },
        ],
      };

      const matchingUsers = await User.find(
        userFilter
      )
        .select("_id")
        .limit(500)
        .lean();

      const userIds = matchingUsers.map(
        (user) => user._id
      );

      const searchConditions = [
        {
          reference: searchRegex,
        },
        {
          transactionReference:
            searchRegex,
        },
        {
          paymentReference:
            searchRegex,
        },
        {
          description: searchRegex,
        },
        {
          narration: searchRegex,
        },
        {
          phone: searchRegex,
        },
        {
          customerPhone: searchRegex,
        },
        {
          customerName: searchRegex,
        },
        {
          userName: searchRegex,
        },
      ];

      if (
        mongoose.Types.ObjectId.isValid(
          search
        )
      ) {
        searchConditions.push({
          _id: new mongoose.Types.ObjectId(
            search
          ),
        });
      }

      if (userIds.length > 0) {
        searchConditions.push(
          {
            customerId: {
              $in: userIds,
            },
          },
          {
            userId: {
              $in: userIds,
            },
          }
        );
      }

      filter.$or = searchConditions;
    }

    const [
      transactions,
      totalTransactions,
    ] = await Promise.all([
      Transaction.find(filter)
        .populate(
          "customerId",
          "fullName name email phone role status"
        )
        .populate(
          "userId",
          "fullName name email phone role status"
        )
        .sort({
          createdAt: -1,
        })
        .skip(skip)
        .limit(limit)
        .lean(),

      Transaction.countDocuments(filter),
    ]);

    const totalPages = Math.max(
      1,
      Math.ceil(
        totalTransactions / limit
      )
    );

    return res.status(200).json({
      success: true,
      message:
        "Transactions loaded successfully.",

      data: {
        transactions,

        pagination: {
          page,
          currentPage: page,
          limit,
          total: totalTransactions,
          totalItems: totalTransactions,
          totalPages,
          hasNextPage:
            page < totalPages,
          hasPreviousPage:
            page > 1,
        },

        total: totalTransactions,
        totalTransactions,
        currentPage: page,
        totalPages,
      },
    });
  } catch (error) {
    console.error(
      "Get admin transactions error:",
      error
    );

    return res.status(500).json({
      success: false,
      message:
        "Failed to load admin transactions.",
      error: error.message,
    });
  }
};