extends RefCounted
# Immutable authored data from source HEAD 9ad6a44daecd4ec36a8172d83ff27493feffe5dd.
const DATA = {
  "GOODS": [
    "grain",
    "wood",
    "iron",
    "silk",
    "porcelain",
    "spices"
  ],
  "GOOD_NAMES": {
    "grain": "粮食",
    "wood": "木材",
    "iron": "铁料",
    "silk": "丝绸",
    "porcelain": "瓷器",
    "spices": "香料"
  },
  "PORTS": [
    {
      "id": "xiamen",
      "name": "厦门",
      "faction": "zheng",
      "islandX": -480,
      "islandZ": -60,
      "radius": 185,
      "peak": 58,
      "x": -306.2570958447386,
      "z": -38.28213698059233,
      "prices": {
        "grain": 4,
        "wood": 8,
        "iron": 14,
        "silk": 32,
        "porcelain": 25,
        "spices": 48
      },
      "stock": {
        "grain": 120,
        "wood": 80,
        "iron": 60,
        "silk": 30,
        "porcelain": 35,
        "spices": 25
      },
      "tax": 0.05,
      "services": [
        "trade",
        "repair",
        "recruit",
        "shipyard",
        "banquet"
      ]
    },
    {
      "id": "kinmen",
      "name": "金门",
      "faction": "zheng",
      "islandX": 420,
      "islandZ": 160,
      "radius": 160,
      "peak": 48,
      "x": 282.1499288930165,
      "z": 107.48568719733964,
      "prices": {
        "grain": 8,
        "wood": 11,
        "iron": 19,
        "silk": 40,
        "porcelain": 32,
        "spices": 52
      },
      "stock": {
        "grain": 120,
        "wood": 80,
        "iron": 60,
        "silk": 30,
        "porcelain": 35,
        "spices": 25
      },
      "tax": 0.05,
      "services": [
        "trade",
        "repair",
        "recruit",
        "shipyard",
        "banquet"
      ]
    },
    {
      "id": "quanzhou",
      "name": "泉州",
      "faction": "qing",
      "islandX": -680,
      "islandZ": -550,
      "radius": 205,
      "peak": 66,
      "x": -541.3493025434773,
      "z": -437.85605352781255,
      "prices": {
        "grain": 6,
        "wood": 7,
        "iron": 10,
        "silk": 23,
        "porcelain": 18,
        "spices": 55
      },
      "stock": {
        "grain": 120,
        "wood": 80,
        "iron": 60,
        "silk": 30,
        "porcelain": 35,
        "spices": 25
      },
      "tax": 0.05,
      "services": [
        "trade",
        "repair",
        "recruit",
        "shipyard",
        "banquet"
      ]
    },
    {
      "id": "penghu",
      "name": "澎湖",
      "faction": "zheng",
      "islandX": 760,
      "islandZ": -420,
      "radius": 145,
      "peak": 36,
      "x": 645.7700269479615,
      "z": -356.87290962913664,
      "prices": {
        "grain": 10,
        "wood": 17,
        "iron": 24,
        "silk": 48,
        "porcelain": 40,
        "spices": 60
      },
      "stock": {
        "grain": 120,
        "wood": 80,
        "iron": 60,
        "silk": 30,
        "porcelain": 35,
        "spices": 25
      },
      "tax": 0.05,
      "services": [
        "trade",
        "repair",
        "recruit",
        "shipyard",
        "banquet"
      ]
    },
    {
      "id": "luermen",
      "name": "鹿耳门",
      "faction": "voc",
      "islandX": 1150,
      "islandZ": 450,
      "radius": 245,
      "peak": 76,
      "x": 939.9416349110738,
      "z": 367.80324844346364,
      "prices": {
        "grain": 9,
        "wood": 13,
        "iron": 18,
        "silk": 45,
        "porcelain": 37,
        "spices": 30
      },
      "stock": {
        "grain": 120,
        "wood": 80,
        "iron": 60,
        "silk": 30,
        "porcelain": 35,
        "spices": 25
      },
      "tax": 0.12,
      "services": [
        "trade",
        "repair",
        "recruit",
        "shipyard",
        "banquet"
      ]
    },
    {
      "id": "dongshan",
      "name": "东山",
      "faction": "pirates",
      "islandX": -280,
      "islandZ": 740,
      "radius": 170,
      "peak": 46,
      "x": -232.142016765827,
      "z": 613.5181871668285,
      "prices": {
        "grain": 7,
        "wood": 6,
        "iron": 20,
        "silk": 38,
        "porcelain": 34,
        "spices": 44
      },
      "stock": {
        "grain": 120,
        "wood": 80,
        "iron": 60,
        "silk": 30,
        "porcelain": 35,
        "spices": 25
      },
      "tax": 0.03,
      "services": [
        "trade",
        "repair",
        "recruit",
        "banquet"
      ]
    }
  ],
  "SHIP_PROFILES": {
    "fisherman": {
      "kind": "fisherman",
      "name": "沿海渔船",
      "price": 320,
      "hull": 100,
      "sail": 100,
      "crew": 24,
      "capacity": 45,
      "speed": 1.05,
      "cannons": 0,
      "minCrew": 4
    },
    "patrol": {
      "kind": "patrol",
      "name": "快艇战船",
      "price": 700,
      "hull": 100,
      "sail": 100,
      "crew": 60,
      "capacity": 70,
      "speed": 1.35,
      "cannons": 3,
      "minCrew": 12
    },
    "fuchuan": {
      "kind": "fuchuan",
      "name": "郑氏福船",
      "price": 1000,
      "hull": 100,
      "sail": 100,
      "crew": 100,
      "capacity": 120,
      "speed": 1,
      "cannons": 4,
      "minCrew": 24
    },
    "merchant": {
      "kind": "merchant",
      "name": "中国贸易船",
      "price": 850,
      "hull": 100,
      "sail": 100,
      "crew": 70,
      "capacity": 220,
      "speed": 0.85,
      "cannons": 0,
      "minCrew": 14
    },
    "voc": {
      "kind": "voc",
      "name": "VOC武装商船",
      "price": 1600,
      "hull": 100,
      "sail": 100,
      "crew": 120,
      "capacity": 180,
      "speed": 0.9,
      "cannons": 4,
      "minCrew": 30
    },
    "heavy": {
      "kind": "heavy",
      "name": "重型战舰",
      "price": 2400,
      "hull": 100,
      "sail": 100,
      "crew": 160,
      "capacity": 150,
      "speed": 0.7,
      "cannons": 8,
      "minCrew": 40
    }
  },
  "LAND_SITES": [
    {
      "id": "kinmen-shrine",
      "name": "金门古祠",
      "portId": "kinmen",
      "kind": "clue",
      "x": 450,
      "z": 160,
      "reward": 0
    },
    {
      "id": "penghu-beacon",
      "name": "澎湖石灯",
      "portId": "penghu",
      "kind": "clue",
      "x": 760,
      "z": -430,
      "reward": 0
    },
    {
      "id": "dongshan-cave",
      "name": "东山海洞",
      "portId": "dongshan",
      "kind": "clue",
      "x": -270,
      "z": 740,
      "reward": 0
    },
    {
      "id": "treasure-cove",
      "name": "藏银湾",
      "portId": "dongshan",
      "kind": "treasure",
      "x": -320,
      "z": 700,
      "reward": 800
    },
    {
      "id": "taiwan-fort",
      "name": "鹿耳门炮台",
      "portId": "luermen",
      "kind": "fort",
      "x": 1120,
      "z": 420,
      "reward": 600
    }
  ],
  "MAIN_QUESTS": [
    {
      "id": "main-1",
      "mainStep": 1,
      "title": "金门军粮",
      "description": "从厦门运送十袋粮食至金门，支援郑氏水师。",
      "kind": "delivery",
      "status": "available",
      "issuerPortId": "xiamen",
      "destinationPortId": "kinmen",
      "good": "grain",
      "quantity": 10,
      "reward": 280,
      "fame": 12,
      "faction": "zheng",
      "deadlineDays": 10,
      "progress": 0,
      "required": 10
    },
    {
      "id": "main-2",
      "mainStep": 2,
      "title": "护航澎湖",
      "description": "护送金门补给船抵达澎湖。补给船必须存活并真正抵达锚地。",
      "kind": "escort",
      "status": "available",
      "issuerPortId": "kinmen",
      "destinationPortId": "penghu",
      "targetId": "escort-penghu",
      "reward": 400,
      "fame": 18,
      "faction": "zheng",
      "deadlineDays": 14,
      "progress": 0,
      "required": 1
    },
    {
      "id": "main-3",
      "mainStep": 3,
      "title": "东山剿寇",
      "description": "击败或降服盘踞东山外海的海盗首船。",
      "kind": "bounty",
      "status": "available",
      "issuerPortId": "penghu",
      "destinationPortId": "dongshan",
      "targetId": "pirate-dongshan",
      "reward": 500,
      "fame": 24,
      "faction": "zheng",
      "deadlineDays": 16,
      "progress": 0,
      "required": 1
    },
    {
      "id": "main-4",
      "mainStep": 4,
      "title": "三岛密图",
      "description": "在金门古祠、澎湖石灯、东山海洞获得三处藏宝线索。",
      "kind": "clues",
      "status": "available",
      "issuerPortId": "kinmen",
      "reward": 250,
      "fame": 20,
      "faction": "zheng",
      "deadlineDays": 25,
      "progress": 0,
      "required": 3
    },
    {
      "id": "main-5",
      "mainStep": 5,
      "title": "夺取航海密令",
      "description": "在鹿耳门外海接舷VOC船长的武装商船并赢得决斗。",
      "kind": "boarding",
      "status": "available",
      "issuerPortId": "kinmen",
      "destinationPortId": "luermen",
      "targetId": "voc-captain",
      "reward": 700,
      "fame": 30,
      "faction": "zheng",
      "deadlineDays": 20,
      "progress": 0,
      "required": 1
    },
    {
      "id": "main-6",
      "mainStep": 6,
      "title": "逐浪台湾",
      "description": "击败鹿耳门守舰，再登岸夺取炮台；回金门报告战果。背景取材1661年，船长与支线角色为虚构。",
      "kind": "finale",
      "status": "available",
      "issuerPortId": "kinmen",
      "destinationPortId": "luermen",
      "targetId": "taiwan-guard",
      "siteId": "taiwan-fort",
      "reward": 1200,
      "fame": 60,
      "faction": "zheng",
      "deadlineDays": 30,
      "progress": 0,
      "required": 2
    }
  ],
  "OFFICERS": {
    "gunner": {
      "role": "gunner",
      "name": "梁火生",
      "description": "炮术官：下次装填耗时减少20%，既有装填不会重置。",
      "price": 180,
      "dailyWage": 1,
      "reloadMultiplier": 0.8,
      "speedMultiplier": 1,
      "supplyFactor": 1
    },
    "sailmaker": {
      "role": "sailmaker",
      "name": "林帆娘",
      "description": "帆缆官：全舰队帆力效率提高，航速倍率增加8%。",
      "price": 160,
      "dailyWage": 1,
      "reloadMultiplier": 1,
      "speedMultiplier": 1.08,
      "supplyFactor": 1
    },
    "cook": {
      "role": "cook",
      "name": "何灶安",
      "description": "伙食官：每日粮耗按常规75%向下取整，至少一袋；薪银每日一两。",
      "price": 120,
      "dailyWage": 1,
      "reloadMultiplier": 1,
      "speedMultiplier": 1,
      "supplyFactor": 0.75
    }
  },
  "AMMO_PRICES": {
    "solid": 3,
    "chain": 4,
    "grape": 2
  },
  "AMMO_STOCKS": {
    "solid": 80,
    "chain": 60,
    "grape": 80
  },
  "AMMO_IRON_BATCH": {
    "solid": 10,
    "chain": 12,
    "grape": 20
  },
  "AMBIENT_VESSELS": [
    {
      "id": "ambient-zheng-trader",
      "name": "郑氏沿海商船",
      "kind": "merchant",
      "faction": "zheng",
      "team": "neutral",
      "homePortId": "xiamen",
      "routePortIds": [
        "xiamen",
        "kinmen"
      ],
      "spawn": {
        "outward": 85,
        "lateral": -30
      },
      "hull": 100,
      "crew": 60,
      "cargoMass": 2000,
      "speedMultiplier": 0.85
    },
    {
      "id": "ambient-qing-fisher",
      "name": "泉州渔船",
      "kind": "fisherman",
      "faction": "qing",
      "team": "neutral",
      "homePortId": "xiamen",
      "routePortIds": [
        "xiamen",
        "quanzhou"
      ],
      "spawn": {
        "outward": 145,
        "lateral": 50
      },
      "hull": 85,
      "crew": 20,
      "cargoMass": 500,
      "speedMultiplier": 1.05
    },
    {
      "id": "ambient-pirate-patrol",
      "name": "东山海盗快船",
      "kind": "patrol",
      "faction": "pirates",
      "team": "hostile",
      "homePortId": "dongshan",
      "routePortIds": [
        "dongshan",
        "penghu"
      ],
      "spawn": {
        "outward": 150,
        "lateral": 360
      },
      "hull": 90,
      "crew": 45,
      "cargoMass": 800,
      "speedMultiplier": 1.1
    }
  ]
}
