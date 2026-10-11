extends RefCounted
# Exact source catalog; exporter embeds pure data, no runtime file access.
const DATA = {
  "ports": {
    "xiamen": {
      "id": "xiamen",
      "name": "厦门",
      "position": {
        "x": -306.2570958447386,
        "z": -38.28213698059233
      },
      "stock": {
        "grain": 90
      },
      "production": {
        "grain": 4
      },
      "consumption": {
        "grain": 1
      }
    },
    "kinmen": {
      "id": "kinmen",
      "name": "金门",
      "position": {
        "x": 282.1499288930165,
        "z": 107.48568719733964
      },
      "stock": {
        "grain": 0
      },
      "production": {},
      "consumption": {
        "grain": 2
      }
    },
    "forward-supply": {
      "id": "forward-supply",
      "name": "近岸补给点",
      "position": {
        "x": -60,
        "z": 320
      },
      "stock": {
        "grain": 0
      },
      "production": {},
      "consumption": {}
    }
  },
  "profiles": {
    "flagship": {
      "id": "flagship",
      "modelKind": "fuchuan",
      "maxHull": 100,
      "maxSail": 100,
      "maxCrew": 80,
      "capacity": 80,
      "baseDraftMeters": 3.2,
      "cargoDraftMetersPerUnit": 0,
      "complement": 60,
      "speedMultiplier": 1,
      "refitProfileId": "flagship-sails"
    },
    "flagship-sails": {
      "id": "flagship-sails",
      "modelKind": "fuchuan",
      "maxHull": 100,
      "maxSail": 100,
      "maxCrew": 80,
      "capacity": 80,
      "baseDraftMeters": 3.2,
      "cargoDraftMetersPerUnit": 0,
      "complement": 60,
      "speedMultiplier": 1.1,
      "refitProfileId": null
    },
    "heritage": {
      "id": "heritage",
      "modelKind": "merchant",
      "maxHull": 100,
      "maxSail": 100,
      "maxCrew": 20,
      "capacity": 40,
      "baseDraftMeters": 1.2,
      "cargoDraftMetersPerUnit": 0.02,
      "complement": 12,
      "speedMultiplier": 1,
      "refitProfileId": "heritage-sails"
    },
    "heritage-sails": {
      "id": "heritage-sails",
      "modelKind": "merchant",
      "maxHull": 100,
      "maxSail": 100,
      "maxCrew": 20,
      "capacity": 40,
      "baseDraftMeters": 1.2,
      "cargoDraftMetersPerUnit": 0.02,
      "complement": 12,
      "speedMultiplier": 1.1,
      "refitProfileId": null
    },
    "grain": {
      "id": "grain",
      "modelKind": "merchant",
      "maxHull": 100,
      "maxSail": 100,
      "maxCrew": 30,
      "capacity": 60,
      "baseDraftMeters": 1.2,
      "cargoDraftMetersPerUnit": 0.02,
      "complement": 20,
      "speedMultiplier": 1,
      "refitProfileId": "grain-sails"
    },
    "grain-sails": {
      "id": "grain-sails",
      "modelKind": "merchant",
      "maxHull": 100,
      "maxSail": 100,
      "maxCrew": 30,
      "capacity": 60,
      "baseDraftMeters": 1.2,
      "cargoDraftMetersPerUnit": 0.02,
      "complement": 20,
      "speedMultiplier": 1.1,
      "refitProfileId": null
    },
    "fast": {
      "id": "fast",
      "modelKind": "patrol",
      "maxHull": 100,
      "maxSail": 100,
      "maxCrew": 30,
      "capacity": 20,
      "baseDraftMeters": 1,
      "cargoDraftMetersPerUnit": 0.01,
      "complement": 18,
      "speedMultiplier": 1,
      "refitProfileId": "fast-sails"
    },
    "fast-sails": {
      "id": "fast-sails",
      "modelKind": "patrol",
      "maxHull": 100,
      "maxSail": 100,
      "maxCrew": 30,
      "capacity": 20,
      "baseDraftMeters": 1,
      "cargoDraftMetersPerUnit": 0.01,
      "complement": 18,
      "speedMultiplier": 1.1,
      "refitProfileId": null
    },
    "enemy": {
      "id": "enemy",
      "modelKind": "fuchuan",
      "maxHull": 100,
      "maxSail": 100,
      "maxCrew": 60,
      "capacity": 60,
      "baseDraftMeters": 2.8,
      "cargoDraftMetersPerUnit": 0.01,
      "complement": 30,
      "speedMultiplier": 1,
      "refitProfileId": "enemy-sails"
    },
    "enemy-sails": {
      "id": "enemy-sails",
      "modelKind": "fuchuan",
      "maxHull": 100,
      "maxSail": 100,
      "maxCrew": 60,
      "capacity": 60,
      "baseDraftMeters": 2.8,
      "cargoDraftMetersPerUnit": 0.01,
      "complement": 30,
      "speedMultiplier": 1.1,
      "refitProfileId": null
    },
    "background": {
      "id": "background",
      "modelKind": "merchant",
      "maxHull": 100,
      "maxSail": 100,
      "maxCrew": 30,
      "capacity": 60,
      "baseDraftMeters": 1.2,
      "cargoDraftMetersPerUnit": 0.02,
      "complement": 16,
      "speedMultiplier": 1,
      "refitProfileId": "background-sails"
    },
    "background-sails": {
      "id": "background-sails",
      "modelKind": "merchant",
      "maxHull": 100,
      "maxSail": 100,
      "maxCrew": 30,
      "capacity": 60,
      "baseDraftMeters": 1.2,
      "cargoDraftMetersPerUnit": 0.02,
      "complement": 16,
      "speedMultiplier": 1.1,
      "refitProfileId": null
    }
  },
  "routes": {
    "xiamen-kinmen-deep": {
      "id": "xiamen-kinmen-deep",
      "originId": "xiamen",
      "destinationId": "kinmen",
      "points": [
        {
          "x": -306.2570958447386,
          "z": -38.28213698059233
        },
        {
          "x": -133.26896858635538,
          "z": -232.37992481108162
        },
        {
          "x": 219.77524625629772,
          "z": -144.91923030432244
        },
        {
          "x": 282.1499288930165,
          "z": 107.48568719733964
        }
      ],
      "minimumDepth": 8
    },
    "xiamen-kinmen-shallow": {
      "id": "xiamen-kinmen-shallow",
      "originId": "xiamen",
      "destinationId": "kinmen",
      "points": [
        {
          "x": -306.2570958447386,
          "z": -38.28213698059233
        },
        {
          "x": -188.5756908971876,
          "z": -9.128572145005933
        },
        {
          "x": 164.4685239454655,
          "z": 78.33212236175325
        },
        {
          "x": 282.1499288930165,
          "z": 107.48568719733964
        }
      ],
      "minimumDepth": 2.4
    },
    "xiamen-kinmen-outer": {
      "id": "xiamen-kinmen-outer",
      "originId": "xiamen",
      "destinationId": "kinmen",
      "points": [
        {
          "x": -306.2570958447386,
          "z": -38.28213698059233
        },
        {
          "x": -280.5166847463205,
          "z": 235.95413096427
        },
        {
          "x": 131.3682325701081,
          "z": 337.9916078888224
        },
        {
          "x": 282.1499288930165,
          "z": 107.48568719733964
        }
      ],
      "minimumDepth": 8
    },
    "kinmen-supply-deep": {
      "id": "kinmen-supply-deep",
      "originId": "kinmen",
      "destinationId": "forward-supply",
      "points": [
        {
          "x": 282.1499288930165,
          "z": 107.48568719733964
        },
        {
          "x": 131.3682325701081,
          "z": 337.9916078888224
        },
        {
          "x": -60,
          "z": 250
        },
        {
          "x": -60,
          "z": 320
        }
      ],
      "minimumDepth": 8
    }
  },
  "roles": [
    {
      "suffix": "flagship",
      "name": "借用福船明旗号",
      "profileId": "flagship",
      "ownerId": "house-lin",
      "able": 60,
      "minimum": 20,
      "armed": true,
      "representation": "near",
      "position": {
        "x": -272.0274644069089,
        "z": -50.40690687309362
      }
    },
    {
      "suffix": "heritage",
      "name": "继承商船承家号",
      "profileId": "heritage",
      "ownerId": "captain",
      "able": 12,
      "minimum": 8,
      "armed": false,
      "representation": "near",
      "position": {
        "x": -290.6269351916773,
        "z": -101.37491056013546
      }
    },
    {
      "suffix": "grain-a",
      "name": "粮船甲",
      "profileId": "grain",
      "ownerId": "house-lin",
      "able": 20,
      "minimum": 8,
      "armed": false,
      "representation": "near",
      "position": {
        "x": -217.61345212267577,
        "z": -93.58935220948257
      }
    },
    {
      "suffix": "grain-b",
      "name": "粮船乙",
      "profileId": "grain",
      "ownerId": "house-lin",
      "able": 20,
      "minimum": 8,
      "armed": false,
      "representation": "near",
      "position": {
        "x": -161.9971197882071,
        "z": -141.625087821221
      }
    },
    {
      "suffix": "fast",
      "name": "雇佣快船逐浪号",
      "profileId": "fast",
      "ownerId": "house-lin",
      "able": 18,
      "minimum": 8,
      "armed": true,
      "representation": "near",
      "position": {
        "x": -164.91187990387752,
        "z": -29.021988796415332
      }
    },
    {
      "suffix": "enemy",
      "name": "敌炮舰",
      "profileId": "enemy",
      "ownerId": "enemy",
      "able": 30,
      "minimum": 12,
      "armed": true,
      "representation": "route",
      "position": {
        "x": 319.4948304380796,
        "z": -295.3543172484113
      }
    },
    {
      "suffix": "background-grain-01",
      "name": "林家运粮商船",
      "profileId": "background",
      "ownerId": "house-lin",
      "able": 16,
      "minimum": 8,
      "armed": false,
      "representation": "route",
      "position": {
        "x": -133.41492856188165,
        "z": 272.396087008753
      }
    }
  ],
  "spawn": {
    "flagship": {
      "x": -272.0274644069089,
      "z": -50.40690687309362
    },
    "heritage": {
      "x": -290.6269351916773,
      "z": -101.37491056013546
    },
    "grain-a": {
      "x": -217.61345212267577,
      "z": -93.58935220948257
    },
    "grain-b": {
      "x": -161.9971197882071,
      "z": -141.625087821221
    },
    "fast": {
      "x": -164.91187990387752,
      "z": -29.021988796415332
    },
    "enemy": {
      "x": 319.4948304380796,
      "z": -295.3543172484113
    },
    "background-grain-01": {
      "x": -133.41492856188165,
      "z": 272.396087008753
    }
  }
}
