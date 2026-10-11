import type { Good, Port, Cargo, ShipProfile, AdventureShipKind, LandSite, Quest, OfficerRole, OfficerProfile, Ammunition, AmmoStock, AmbientVesselProfile } from './types.js'

export const GOODS: readonly Good[] = ['grain', 'wood', 'iron', 'silk', 'porcelain', 'spices']
export const GOOD_NAMES: Record<Good, string> = { grain: '粮食', wood: '木材', iron: '铁料', silk: '丝绸', porcelain: '瓷器', spices: '香料' }
export const emptyCargo = (): Cargo => ({ grain: 0, wood: 0, iron: 0, silk: 0, porcelain: 0, spices: 0 })
export const AMMO_PRICES: Record<Ammunition, number> = {solid:3,chain:4,grape:2}
export const AMMO_STOCKS: AmmoStock = {solid:80,chain:60,grape:80}
export const AMMO_IRON_BATCH: Record<Ammunition, number> = {solid:10,chain:12,grape:20}
export const OFFICERS: Record<OfficerRole, OfficerProfile> = {
  gunner:{role:'gunner',name:'梁火生',description:'炮术官：下次装填耗时减少20%，既有装填不会重置。',price:180,dailyWage:1,reloadMultiplier:0.8,speedMultiplier:1,supplyFactor:1},
  sailmaker:{role:'sailmaker',name:'林帆娘',description:'帆缆官：全舰队帆力效率提高，航速倍率增加8%。',price:160,dailyWage:1,reloadMultiplier:1,speedMultiplier:1.08,supplyFactor:1},
  cook:{role:'cook',name:'何灶安',description:'伙食官：每日粮耗按常规75%向下取整，至少一袋；薪银每日一两。',price:120,dailyWage:1,reloadMultiplier:1,speedMultiplier:1,supplyFactor:0.75}
}
const islands = [
  {id:'xiamen',name:'厦门',faction:'zheng',islandX:-480,islandZ:-60,radius:185,peak:58},
  {id:'kinmen',name:'金门',faction:'zheng',islandX:420,islandZ:160,radius:160,peak:48},
  {id:'quanzhou',name:'泉州',faction:'qing',islandX:-680,islandZ:-550,radius:205,peak:66},
  {id:'penghu',name:'澎湖',faction:'zheng',islandX:760,islandZ:-420,radius:145,peak:36},
  {id:'luermen',name:'鹿耳门',faction:'voc',islandX:1150,islandZ:450,radius:245,peak:76},
  {id:'dongshan',name:'东山',faction:'pirates',islandX:-280,islandZ:740,radius:170,peak:46}
] as const
const prices: Record<string, number[]> = {
  xiamen: [4, 8, 14, 32, 25, 48], kinmen: [8, 11, 19, 40, 32, 52],
  quanzhou: [6, 7, 10, 23, 18, 55], penghu: [10, 17, 24, 48, 40, 60],
  luermen: [9, 13, 18, 45, 37, 30], dongshan: [7, 6, 20, 38, 34, 44]
}
export const PORTS: readonly Port[] = islands.map(island => {
  const length = Math.hypot(island.islandX,island.islandZ)
  const nx=-island.islandX/length, nz=-island.islandZ/length
  const reach=1/Math.sqrt(nx*nx/(island.radius*island.radius)+nz*nz/(island.radius*0.82)**2)
  return {...island,x:island.islandX+nx*reach*0.95,z:island.islandZ+nz*reach*0.95,
    prices: Object.fromEntries(GOODS.map((g, i) => [g, prices[island.id][i]])) as Cargo,
    stock: { grain: 120, wood: 80, iron: 60, silk: 30, porcelain: 35, spices: 25 },
    tax: island.faction === 'voc' ? 0.12 : island.faction === 'pirates' ? 0.03 : 0.05,
    services: island.id === 'dongshan' ? ['trade', 'repair', 'recruit', 'banquet'] : ['trade', 'repair', 'recruit', 'shipyard', 'banquet']}
})
export const SHIP_PROFILES: Record<AdventureShipKind, ShipProfile> = {
  fisherman: { kind:'fisherman',name:'沿海渔船',price:320,hull:100,sail:100,crew:24,capacity:45,speed:1.05,cannons:0,minCrew:4 },
  patrol: { kind:'patrol',name:'快艇战船',price:700,hull:100,sail:100,crew:60,capacity:70,speed:1.35,cannons:3,minCrew:12 },
  fuchuan: { kind:'fuchuan',name:'郑氏福船',price:1000,hull:100,sail:100,crew:100,capacity:120,speed:1,cannons:4,minCrew:24 },
  merchant: { kind:'merchant',name:'中国贸易船',price:850,hull:100,sail:100,crew:70,capacity:220,speed:0.85,cannons:0,minCrew:14 },
  voc: { kind:'voc',name:'VOC武装商船',price:1600,hull:100,sail:100,crew:120,capacity:180,speed:0.9,cannons:4,minCrew:30 },
  heavy: { kind:'heavy',name:'重型战舰',price:2400,hull:100,sail:100,crew:160,capacity:150,speed:0.7,cannons:8,minCrew:40 }
}
/** One persistent vessel of each role per voyage; IDs never enter quest factories. */
export const AMBIENT_VESSELS:readonly AmbientVesselProfile[]=[
  {id:'ambient-zheng-trader',name:'郑氏沿海商船',kind:'merchant',faction:'zheng',team:'neutral',homePortId:'xiamen',routePortIds:['xiamen','kinmen'],spawn:{outward:85,lateral:-30},hull:100,crew:60,cargoMass:2000,speedMultiplier:.85},
  {id:'ambient-qing-fisher',name:'泉州渔船',kind:'fisherman',faction:'qing',team:'neutral',homePortId:'xiamen',routePortIds:['xiamen','quanzhou'],spawn:{outward:145,lateral:50},hull:85,crew:20,cargoMass:500,speedMultiplier:1.05},
  {id:'ambient-pirate-patrol',name:'东山海盗快船',kind:'patrol',faction:'pirates',team:'hostile',homePortId:'dongshan',routePortIds:['dongshan','penghu'],spawn:{outward:150,lateral:360},hull:90,crew:45,cargoMass:800,speedMultiplier:1.1},
]
export const LAND_SITES: readonly LandSite[] = [
  { id:'kinmen-shrine',name:'金门古祠',portId:'kinmen',kind:'clue',x:450,z:160,reward:0 },
  { id:'penghu-beacon',name:'澎湖石灯',portId:'penghu',kind:'clue',x:760,z:-430,reward:0 },
  { id:'dongshan-cave',name:'东山海洞',portId:'dongshan',kind:'clue',x:-270,z:740,reward:0 },
  { id:'treasure-cove',name:'藏银湾',portId:'dongshan',kind:'treasure',x:-320,z:700,reward:800 },
  { id:'taiwan-fort',name:'鹿耳门炮台',portId:'luermen',kind:'fort',x:1120,z:420,reward:600 }
]
export const MAIN_QUESTS: readonly Quest[] = [
  {id:'main-1',mainStep:1,title:'金门军粮',description:'从厦门运送十袋粮食至金门，支援郑氏水师。',kind:'delivery',status:'available',issuerPortId:'xiamen',destinationPortId:'kinmen',good:'grain',quantity:10,reward:280,fame:12,faction:'zheng',deadlineDays:10,progress:0,required:10},
  {id:'main-2',mainStep:2,title:'护航澎湖',description:'护送金门补给船抵达澎湖。补给船必须存活并真正抵达锚地。',kind:'escort',status:'available',issuerPortId:'kinmen',destinationPortId:'penghu',targetId:'escort-penghu',reward:400,fame:18,faction:'zheng',deadlineDays:14,progress:0,required:1},
  {id:'main-3',mainStep:3,title:'东山剿寇',description:'击败或降服盘踞东山外海的海盗首船。',kind:'bounty',status:'available',issuerPortId:'penghu',destinationPortId:'dongshan',targetId:'pirate-dongshan',reward:500,fame:24,faction:'zheng',deadlineDays:16,progress:0,required:1},
  {id:'main-4',mainStep:4,title:'三岛密图',description:'在金门古祠、澎湖石灯、东山海洞获得三处藏宝线索。',kind:'clues',status:'available',issuerPortId:'kinmen',reward:250,fame:20,faction:'zheng',deadlineDays:25,progress:0,required:3},
  {id:'main-5',mainStep:5,title:'夺取航海密令',description:'在鹿耳门外海接舷VOC船长的武装商船并赢得决斗。',kind:'boarding',status:'available',issuerPortId:'kinmen',destinationPortId:'luermen',targetId:'voc-captain',reward:700,fame:30,faction:'zheng',deadlineDays:20,progress:0,required:1},
  {id:'main-6',mainStep:6,title:'逐浪台湾',description:'击败鹿耳门守舰，再登岸夺取炮台；回金门报告战果。背景取材1661年，船长与支线角色为虚构。',kind:'finale',status:'available',issuerPortId:'kinmen',destinationPortId:'luermen',targetId:'taiwan-guard',siteId:'taiwan-fort',reward:1200,fame:60,faction:'zheng',deadlineDays:30,progress:0,required:2}
]

// Catalog references can be shared with the UI without exposing rule authority.
Object.freeze(GOODS)
Object.freeze(GOOD_NAMES)
Object.freeze(AMMO_PRICES);Object.freeze(AMMO_STOCKS);Object.freeze(AMMO_IRON_BATCH)
for(const officer of Object.values(OFFICERS))Object.freeze(officer)
Object.freeze(OFFICERS)
for(const port of PORTS) {Object.freeze(port.prices);Object.freeze(port.stock);Object.freeze(port.services);Object.freeze(port)}
Object.freeze(PORTS)
for(const profile of Object.values(SHIP_PROFILES))Object.freeze(profile)
Object.freeze(SHIP_PROFILES)
for(const vessel of AMBIENT_VESSELS){Object.freeze(vessel.routePortIds);Object.freeze(vessel.spawn);Object.freeze(vessel)}
Object.freeze(AMBIENT_VESSELS)
for(const site of LAND_SITES)Object.freeze(site)
Object.freeze(LAND_SITES)
for(const quest of MAIN_QUESTS)Object.freeze(quest)
Object.freeze(MAIN_QUESTS)
