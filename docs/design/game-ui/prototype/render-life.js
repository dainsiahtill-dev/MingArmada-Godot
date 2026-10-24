/* Harbor, livelihood, correspondence and relationship screens. */
(() => {
  'use strict';

  const goods = [
    { id: 'silk', name: '生丝', unit: '担', buy: 42, sell: 36, market: 32, origin: '福建来货', demand: '平稳', note: '货色细匀，适合合货远运。', type: 'cargo' },
    { id: 'porcelain', name: '瓷器', unit: '箱', buy: 56, sell: 48, market: 18, origin: '漳泉窑口', demand: '求购', note: '箱内须垫稻草，遇浪易有破损。', type: 'cargo' },
    { id: 'spices', name: '香料', unit: '包', buy: 68, sell: 57, market: 9, origin: '南洋转运', demand: '货少', note: '气味与封口均已验过，来源另见货单。', type: 'cargo' },
    { id: 'grain', name: '米粮', unit: '石', buy: 18, sell: 14, market: 96, origin: '本港粮行', demand: '充足', note: '按船员口数备粮，勿挤占全程余量。', type: 'supplies' },
    { id: 'wood', name: '船用木料', unit: '捆', buy: 28, sell: 22, market: 42, origin: '港内木行', demand: '平稳', note: '可供在航修补；大修仍须进船坞。', type: 'supplies' },
    { id: 'iron', name: '铁料', unit: '箱', buy: 34, sell: 27, market: 26, origin: '本港铁铺', demand: '平稳', note: '钉、箍与常用铁件，分箱便于取用。', type: 'supplies' }
  ];
  const contracts = {
    escort: { title: '同航护送 · 米船过海', client: '本港米行', route: ['平户', '外海会合处', '大员锚地'], reward: 420, days: '6—8日', risk: '有武装船出没', cargo: '不占自有货舱', terms: ['开航前与米船核对船数及信号。', '途中不得临时抽走约定的接应船。', '报酬以米船抵达与货单交验为据。'], note: '米行雇的是一路照应。到了险处，自己的货与护送的船可能不会在同一方向。' },
    delivery: { title: '代运货物 · 生丝十二担', client: '平户合货商', route: ['平户货栈', '赴闽航路', '福建交货点'], reward: 280, days: '5—7日', risk: '注意箱封与货损', cargo: '预留12格货位', terms: ['装船时两边各留一份封货清单。', '不得将托运货混入自有货出售。', '抵埠后验封交付，破损与短少逐项记明。'], note: '薄利的差事也要有人做。货主在意的是这一批货有没有好好到岸。' },
    salvage: { title: '寻回失货 · 漂箱线索', client: '受损船主', route: ['港口询问', '近岸漂流带', '原泊地交验'], reward: 160, days: '2—3日', risk: '归属待辨，不得先卖', cargo: '最多8格临时货位', terms: ['按原主提供的箱印与封条辨认。', '先救落水者，再清点漂货。', '无法核实归属的货物登记封存。'], note: '船沉了，箱子上的名字未必一起沉。带回来的东西仍需有人认。' }
  };
  const factions = [
    { id: 'hirado', name: '平户商人', short: '合货往来', status: '可交涉', interest: '船期、货色与按约结算', reach: '平户货栈与赴闽航路', portrait: 'merchant-woman', detail: '各家自负盈亏，不因同在一港便同进同退。吉平愿意合货，也要看一官先拿出自己的份。' },
    { id: 'fujian', name: '福建海商', short: '有往有来', status: '需逐船约定', interest: '沿海通路、粮货与回援', reach: '闽粤沿海锚地', portrait: 'zheng-captain', detail: '合伙靠各船拿出不可少的东西。分利、损失与发令的边界，不能被一面旗遮住。' },
    { id: 'voc', name: '荷方贸易网络', short: '条件合作', status: '谨慎往来', interest: '货源、通译与武装航次', reach: '大员及周边航路', portrait: 'voc-captain', detail: '商馆、船长与水手的利益并不完全相同。一份委托证明能说明来由，不能保证在所有海面都被承认。' },
    { id: 'armed', name: '过水武装集团', short: '存在争议', status: '提防拦截', interest: '过水费、压货与控制航道', reach: '若干沿岸水路', portrait: 'pirate-captain', detail: '阮老六等人以船与武器索取过水钱。具体人物与遭遇见航海纪事，不代表所有海上商人与水手。' }
  ];
  const intel = [
    { id: 'return-ship', title: '有船可捎回平户', category: 'confirmed', source: '陈添 · 当面问过船主', age: '今日午后', status: '已核实船位', place: '大员泊船处', content: '一条回平户的船可带一人，也可捎小包与家信。是否同行，要在起锚前答复。', limit: '只确认这条船的去向与空位，不代表已替你留下铺位。', action: 'send-letter-remittance', label: '准备托信' },
    { id: 'wind', title: '外海两日后或有顺风', category: 'unverified', source: '候潮水手 · 经验判断', age: '今日清晨', status: '仍需看天', place: '港口潮口', content: '老水手根据云势与风向猜测后日可行。出港前仍应重新看风，不可据此承诺确切抵达日。', limit: '风候可能变化；抵埠时间仍受船况、潮水与同航船影响。', action: 'weather-wind', label: '查看风候' },
    { id: 'red-seal', title: '红封货舱的原主线索', category: 'unverified', source: '受损商户 · 转述', age: '昨日傍晚', status: '尚未交叉核实', place: '隐蔽锚地', content: '有商户称混装的箱子带着别家记号。眼下只有口述，须逐箱辨印，也要听另一方如何说明。', limit: '不能将一名商户的说法当作全部货物的所有权证明。', action: 'black-market', label: '查看待辨货物' }
  ];
  const mail = [
    { id: 'birth', title: '母子平安', from: '田川氏 · 平户', date: '1624年', state: '已收到', excerpt: '孩子哭得响，布够用，亲属来帮。若要再走，别让旁人先告诉我。', image: 'zheng_a2_s4' },
    { id: 'boat', title: '一张船与一段歌', from: '田川氏 · 平户', date: '1624年末—1625年初', state: '已收到', excerpt: '船身是母亲画给幼儿看的，空处留着，等孩子自己添。', image: 'zheng_a2_s5' },
    { id: 'reply', title: '新航之后再回', from: '一官 · 大员船上', date: '1624年', state: '已托寄', excerpt: '先答应了下一航，再将自己的安排写进信里。', image: 'zheng_a2_s4' }
  ];

  const n = value => Number(value || 0).toLocaleString('zh-CN');
  const stock = (state, id) => Number((state.stock || {})[id] || 0);
  const selectedGood = state => goods.find(g => g.id === state.selectedGood) || goods[0];
  const acceptedContractIds = state => [...new Set([
    ...(Array.isArray(state.acceptedContracts) ? state.acceptedContracts : []),
    ...(Array.isArray(state.acceptedContractsIDs) ? state.acceptedContractsIDs : []),
    ...(state.acceptedContract ? [state.acceptedContract] : [])
  ])].filter(id => Object.hasOwn(contracts, id));
  const sentRecords = state => (Array.isArray(state.sentLetterRecords) ? state.sentLetterRecords : []).map(record => ({
    ...record, id: String(record.id), title: record.title || `寄往${record.recipient}的家信`,
    from: `一官 → ${record.recipient}`, state: record.fixture ? '只读寄件样例 · 未实际托寄' : '已托寄 · 尚待回音', image: 'zheng_a2_s4', personal: true,
    excerpt: String(record.body || '').slice(0, 72), date: record.date || '本航托寄'
  }));
  const visibleLetters = state => ['sent', 'unknown', 'transit'].includes(state.letterFilter || 'received')
    ? [...sentRecords(state), ...mail.filter(letter => letter.state !== '已收到')]
    : mail.filter(letter => letter.state === '已收到');
  const set = (ui, key, value, label, cls = 'button') => ui.action('set', label, cls, { key, value });
  const action = (ui, name, label, cls, attrs, disabled = false) => {
    const html = ui.action(name, label, cls || 'button', attrs || {});
    return disabled && !/<button\b[^>]*\sdisabled(?:[\s=>])/.test(html) ? html.replace('<button', '<button disabled aria-disabled="true"') : html;
  };
  const head = (ui, title, desc, actions = '', where = '港口与人间') => ui.pageHead(where, title, desc, actions);
  const scene = (ui, id, alt, cls = '') => `<img class="${cls}" src="${ui.sceneURL(id)}" alt="${ui.e(alt)}" loading="lazy">`;
  const goodImage = (ui, id, cls = 'goods-icon') => `<img class="${cls}" src="${ui.asset(`goods/${id}-v1.png`)}" alt="" loading="lazy">`;
  const portrait = (ui, id, alt, cls = 'portrait') => `<img class="${cls}" src="${ui.asset(`characters/${id}-v1.png`)}" alt="${ui.e(alt)}" loading="lazy">`;
  const fact = (label, value) => `<div class="lp-fact"><span>${label}</span><strong>${value}</strong></div>`;
  const route = (places, cls = '') => `<ol class="lp-route ${cls}">${places.map((p, i) => `<li><span>${i + 1}</span><strong>${p}</strong></li>`).join('')}</ol>`;
  const strip = items => `<div class="lp-strip">${items.join('')}</div>`;
  const cargoWeights = { grain: 1, wood: 2, iron: 2, silk: 1, porcelain: 2, spices: 1 };
  const cargo = (state, ui) => {
    const capacity = Number(state.cargoCapacity || 350);
    const used = ui.cargoUsed ? ui.cargoUsed(state) : Object.entries(state.stock || {}).reduce((sum, [id, qty]) => sum + Number(qty) * (cargoWeights[id] || 1), 0);
    return { capacity, used, free: Math.max(0, capacity - used) };
  };
  const marketAvailable = (state, good) => Number(state.marketStock?.[good.id] ?? good.market);
  const scenarioIs = (state, label) => state.previewScenario === label;
  const stamp = (label, tone = '') => `<span class="lp-status-stamp ${tone}">${label}</span>`;
  const fieldNote = (title, text, tone = '') => `<div class="lp-field-note ${tone}"><strong>${title}</strong><p>${text}</p></div>`;
  const empty = (ui, title, text, target, label) => `<div class="lp-purpose-empty">${ui.icon('book')}<h3>${title}</h3><p>${text}</p>${target ? ui.go(target, label, 'button') : ''}</div>`;
  const lifeScenarios = {
    'port-hub': {
      '澳门货栈': ['货栈催装，先核吃水', '泊处不是所有船都属于你。把装货次序、船主与掌船人的意见核对清楚。', '先验货，再答船期'],
      '平户邻里': ['买卖之外，还有邻里', '货栈、木屋和泊处各有要办的事。不要用一笔远航收益代答家中的归期。', '市集与家门分别进入'],
      '隐蔽锚地': ['先辨货物来路', '此处可换补给、听消息；争议货不能自动变成自有货。', '销货与封存分开'],
      '港火之后': ['先救人船，再复开市', '厦门港火之后的情境展示：市场暂缓，修船、清点与安置入口仍可见。', '贸易入口暂缓开放']
    },
    market: {
      '正常行情': ['可成交的货，先看两种价', '买入与卖出分列，数量受本港余货、银两与加权货位共同限制。', '价格差不等于固定利润'],
      '库存不足': ['当前货位暂无余货', '以选中货物售罄展示空库存行与禁用原因，不凭空补出下一批货。', '换选其他货物仍可看价'],
      '急需补给': ['先为长航程留粮', '按二十日备航示例检查口粮缺口；船上真实数量保持不变。', '优先显示补给货物'],
      '货舱将满': ['余舱需要留给人船', '展示额外封存货占用余舱的冲突；封存示例不会加入自有货库存。', '先理货，再开买单']
    },
    'trade-order': {
      '余额充足': ['逐项算到成交之后', '价银、数量、加权占舱与成交后余额同屏核对。', '数量改变时总额即时更新'],
      '银两不足': ['订单超出当前支用银', '显示超出预算的订单示例及缺口；此示例禁用成交，不扣真实银。', '减少数量或先行筹银'],
      '容量不足': ['订单没有可用货位', '示例将剩余货位留作封存，不能挤入新货；卖出自有货仍是另一种操作。', '不将托运货误卖腾舱'],
      '成交完成': ['成交要留下可查记录', '有本次成交记录时显示真实收支；尚无记录时明确提示还没有成交凭据。', '余额与账房使用同一流水']
    },
    'contract-board': {
      '可接': ['先看责任，再看报酬', '只列尚未承接的差事；已接委托不会因切换浏览而丢失。', '可接与已接分开筛选'],
      '进行中': ['已经答应的事', '按实际承接ID筛选；没有已接记录时展示明确的空册。', '不代造正在执行的航次'],
      '待交割': ['带着凭据来交验', '只列已提交待验收的委托；提交本身不会发放报酬。', '承接、提交、验收三步不同'],
      '有争议': ['约内责任与约外追加', '争议情境提示封货、接应和损失的分界，未经辨认的货不可自动交割。', '争议须留证，不能一键抹平']
    },
    'contract-detail': {
      '待签': ['尚未签下的约', '先核货位、人船与双方所需的交验凭据，接受后才进入日志。', '没有预先领取报酬'],
      '条件不足': ['尚有条件不能答应', '展示接应船或货位不足的情境，签约入口停用并说明缺项。', '保留返回整备的路'],
      '履约待验': ['提交之后还要验明', '只有实际已接委托可以提交；待验状态防止重复提交与重复领银。', '验收仍需后续航次事实'],
      '欠损未清': ['损失不能被完约字样遮住', '先列封货、受伤与接应责任。原型可登记提交，不虚构已经和解。', '赔付与报酬另列']
    },
    'black-market': {
      '普通换货': ['议价也要留余粮', '明示买卖价与本船自有货，只对可辨明的货项开放成交。', '港市库存与此处分别记'],
      '来路待辨': ['箱上的名字还未核实', '封条不一致的货只供查线索，不进入可出售清单。', '原主线索先于出价'],
      '有人追索': ['交易去向可能被问起', '显示追索来源、未核实范围与暂缓销货理由，不套用官府名义。', '民间追索不是公文授权'],
      '买主拒收': ['对方不接这批货', '本次议价货项停用，保留封存与返回市集的入口。', '拒收不等于货物消失']
    },
    supplies: {
      '准备充足': ['够一程，也要留余量', '将现有、目标、缺口、单价与货位并列；数量随船员人数和计划天数计算。', '粮水不能只看货舱总量'],
      '水量不足': ['淡水须逐桶核验', '没有已核水桶记录时明确标为待验，不能凭米粮充足声称水够用。', '本页不虚构淡水库存'],
      '超出预算': ['先补必要的部分', '展示长航程备粮需求高于现银的冲突；按可用预算分批采购。', '不提供负银两采购'],
      '容量冲突': ['补给也占货位', '预留救援与封存空间后，不足的货位会写在各行的禁用理由中。', '不牺牲所有救援余舱']
    },
    'quest-journal': {
      '当前主线': ['今天可以动手的事', '主线目标保留地点、相关人和下一步入口，按已追踪状态显示。', '目标不是任务等级'],
      '待交割': ['已接与待验的委托', '只显示实际承接和提交记录，没有记录时指向委托板。', '不为演示伪造完成'],
      '承诺未清': ['说过的话仍在册中', '家用、归期和同船人安排保留具体对象；寄出后仍区别收到与否。', '钱不能代替全部答复'],
      '已完成': ['已完成的动作留有凭据', '仅从实际寄件和已登记动作生成完成记录；无记录则说明如何留下第一笔。', '不把尚待验收写成完约']
    },
    'quest-detail': {
      '准备执行': ['把下一步说具体', '读信、核对已经答应的航次，再向家中写明安排。', '地点与人物均可回看'],
      '目标进行中': ['已经答应，尚未写完', '追踪标记与实际寄件分别判断，不因点过追踪就完成回信。', '追踪不会推进剧情年份'],
      '完成有代价': ['寄出不等于回家', '即使已经托信，错过这趟可行的回船仍留在后果栏。', '完成动作不抹除缺席'],
      '固定结果': ['这段取舍有已定正线', '本场留下一航与家庭分隔沿用剧情；这里不提供改写史实的奖励按钮。', '可补办事项另行列出']
    },
    chronicle: {
      '历史节点': ['只看有据的年份骨架', '出生、受抚、赴明、料罗湾与分途各带边界说明，不拿插图当现场证据。', '私人对白不归入史料'],
      '跨年概括': ['年份之间也有日子', '展示跨年段落，保留编年不确定处，不凭空补确日。', '不确定的范围照实保留'],
      '原创航次': ['有故事，并非已证史事', '具体漂货、短航与人物抉择标作剧情演绎，不冒称历史第一船或第一战。', '原创建立在既定边界内'],
      '当前年份': ['回到当前选中的一年', '按年筛选生涯节点与相关场次，可随时恢复全编年。', '选年只影响回顾']
    },
    intelligence: {
      '未经核实': ['保留谁说了什么', '单方转述只作待查消息，明确尚不能由此认定的事实。', '可标记等待再问'],
      '相互印证': ['核过的范围仍有限', '回船空位由当面问过船主确认；并未据此确认全部航路安全。', '可信不等于无条件保证'],
      '已证伪': ['旧说法退出行动依据', '以已被在场核验否定的示例展示作废样式，不继续推送为目标。', '此条为状态示例，非新增史事'],
      '已过时': ['旧风信不能定今日的船期', '保留原时间与来源，停用直接据此行动的入口，改为重看风候。', '过时消息仍可追溯']
    },
    relationships: {
      '互利同行': ['各自拿出不能少的东西', '船、熟水手、货源与翻话能力分别形成合作，不压成一条好感值。', '承诺按具体对象留存'],
      '旧恩未偿': ['被救回来的人仍记得代价', '杜七舍货换人、阿旺掌船担险，支持与损失都有具体来因。', '钱与对等地位不是一回事'],
      '关系破裂': ['旧伙伴仍有自己的路', '按剧中断盟情境展示边界，不提供付一次银就自动招回的操作。', '固定损失不变成刷分任务'],
      '有限缓和': ['能再合作的只是眼前这一件', '保留旧事，同时把新的接应条件说清；缓和不等于旧伤清零。', '对方可以继续拒绝']
    },
    factions: {
      '可交易': ['有门路，也有各家的条件', '按海域与具体组织筛选，不把同国籍的人合成一种立场。', '商馆、船长与水手分别看'],
      '临时结盟': ['同航并不交出自己的船', '盟船的掌船、撤回和接应权分列，议定范围之外仍须再问。', '联盟不是自动继承'],
      '通路受制': ['一条水路，有人开价', '显示受制海段与可谈条件，保留绕行与核对凭据的入口。', '通行不能只看旗色'],
      '交战': ['交易入口暂缓', '冲突对象与受影响的通路分别写明，不扩成所有同国籍角色敌对。', '看清组织再发令']
    },
    'faction-detail': {
      '已知条件': ['知道的写清楚', '关键要求、资源与来往事件可查；尚未落实的条件仍标待答复。', '不填补未知名册'],
      '情报不足': ['尚缺能确认的人与货', '隐藏未经核实的能力判断，显示需要询问的事项与来源入口。', '未知不是零实力'],
      '谈判中': ['一份提议不等于盟约', '显示已选事项、我方可承担部分和对方仍未答应的部分。', '条件另在谈判桌登记'],
      '关系紧张': ['交涉须先面对旧事', '把压货、失援或通路争议列为阻碍，不用送礼按钮替代事实。', '可结束会谈再核对']
    },
    diplomacy: {
      '互利可谈': ['桌上只谈这一件事', '合货谈投入与结算，接应谈发令边界，停手谈眼前放行，三份条件分别保留。', '登记提议，等待回应'],
      '条件未落实': ['口头说过，仍未写定', '展示尚缺对方确认的事项，明确不产生自动结盟或利润。', '先补条件，不先领结果'],
      '身份改变': ['官身改变了责任', '受抚后的报效与旧盟身份冲突分别说明，不把官旗当万能通行物。', '历史节点沿生涯推进'],
      '对方拒绝': ['对方可以不答应', '停止重复提交当前提议，保留结束会谈与改谈其他事项。', '拒绝不会扣掉虚构好感']
    },
    'sea-permits': {
      '限段有效': ['文书只在约定范围内有用', '颁发者、适用对象、水域与失效条件逐项可查。', '持有不是普遍豁免'],
      '不被对方承认': ['一方的证明，另一方未必收', '荷方委托可能引来西班牙巡船扣问，不能点击改成全球通行。', '先核对眼前的对方'],
      '旗号冒用': ['同旗也要核船与人', '显示保护旗被滥用时的核验事项；旗色本身不能证明货物归属。', '与船数、封记交叉核对'],
      '凭据已毁': ['纸毁了，来历仍留在纪事里', '按剧情毁纸情境展示失效文书，不提供凭空重印原件。', '改看其他能核实的关系']
    },
    'bounty-board': {
      '民间酬赏': ['私人的托付写明私人身份', '寻货报酬以箱印与见证为据，不使用官府封印装点民间差事。', '承接前先辨权责'],
      '来源存疑': ['钱从谁手里来，还没问清', '不开放承接来源不明的追索，先查发布者与所求。', '风险记录可继续回看'],
      '本人被追索': ['别人也在给你开价', '呈现剧中民间追索风险，不将其伪造为官府通缉。', '不把私雇追索写成公权'],
      '后果已发生': ['损失要回到实际的人', '追索与换人造成的货损、人情和回援承诺分别留册。', '酬银不替代后续责任']
    },
    home: {
      '初立屋檐': ['灯下先有两个人的选择', '平户小屋的日常、当事人的退让与不宽裕的生活分别呈现。', '不扩张成领地建造'],
      '隔海两地': ['船能来，人未必同行', '住所、信路与原定家用分开处理，不用收入图表盖过等待。', '归期未定就照实说'],
      '短暂重聚': ['1645年，屋里与门外的称呼', '母亲仍叫福松，外面已称成功；团聚不意味着立场自动相同。', '私下场面沿剧情演绎'],
      '分途之前': ['1646年，箱子重新放下', '家人各自决定去向，不用一次家用支付改变既定分途。', '家变不作操作惩罚']
    },
    family: {
      '成家': ['共同选择一个屋檐', '两个人都有更省心的另一条路，却各退一步住在这里。', '年份保留约数'],
      '隔海抚育': ['幼儿的日子在岸上', '母亲与亲属照顾孩子，父亲从信里认识他的变化。', '婴儿不会替母亲画船'],
      '迎子赴明': ['1630年的一程，不是一家同行', '亲属照护福松渡海，母亲与幼子留在平户。', '不倒用1635禁令解释此行'],
      '各有决定': ['亲情没有替代人的决定', '晚年的父、母、子各有去向，固定节点不开放付费改写。', '责任不能用指令代答']
    },
    'child-growth': {
      '幼年平户': ['母亲画船，空处仍留着', '按幼年阶段展示照护与来信，不让婴儿作画或参加作战。', '家书里的船不是能力升级'],
      '赴明蒙学': ['先认父亲，再认新的生活', '赴明与教养经历落到具体年份，母亲没有在同一航同行。', '读书不购买立场'],
      '求学成长': ['日渐认定自己的路', '以成长经历描述观念变化，不补造未核实的确日与私人原话。', '父亲不能代答志向'],
      '领受职分': ['森得赐姓，名成功', '1645年的称呼与责任改变，和家中熟悉的福松并置。', '不把荣耀变成属性点']
    },
    letters: {
      '已收到': ['读完后，替对方收好', '来信正文、时间范围与附物线索可打开，收到与读过另作区别。', '私人家书不当作传世档案'],
      '已写未托': ['字写好了，船还没托', '展示当前草稿内容与未托寄原因；空草稿直接给出写信入口。', '写好不等于已经送出'],
      '随船在途': ['已交托，仍在等海路', '只展示真实寄件与剧情留存的回信，不自动标成已收到。', '有寄件才有新回执'],
      '送达不明': ['回音没有到，就保留未知', '托寄记录与收信回音分别列明；没有回音不擅自判定遗失或送达。', '等待不是系统确认']
    },
    'letter-detail': {
      '家书原文展示': ['把阅读留给正文', '纸面正文为主，信路与人物移到页边；玩家实际写下的内容可完整回读。', '长文保留换行'],
      '附船图童谣': ['附物是关系中的一个细节', '展示船图与学歌的剧情线索，不把相关插图冒称历史信件原物。', '母亲初画，留空待孩子长大'],
      '寄款附记': ['银额与信分开核', '有实际寄件才显示具体附银与费用；没有记录时明确写尚无附记。', '寄款在账房另留一行'],
      '回信待写': ['先答那句没有答完的话', '归期、下一航与托话人分别列作回信提示，不替玩家自动发信。', '草稿留在写信页']
    },
    'send-letter-remittance': {
      '待写': ['有些话不能只留在账上', '正文、收信人、家用与托话人各有明确标签，空正文不允许托寄。', '草稿在当前会话保留'],
      '银两待筹': ['先留出捎信费用', '家用与20两捎信费合算，缺口写明；不提供负数汇银。', '可将家用改为零，照实写信'],
      '找到托寄人': ['这条船确认能捎小包', '先核陈添问明的回船，再封信；托寄仍不保证确日收到。', '船路与人情都有边界'],
      '已经托寄': ['实际寄件才有实际回执', '回执保留正文、收信人和金额；没有真实记录时指向当前草稿。', '不会为演示扣第二次银']
    },
    'voyage-result': {
      '顺利交割': ['顺利到港还要分清账', '人船、货物与本次实际出入并列；未验收的委托不冒称结清。', '先看凭据，再说完约'],
      '获利但失援': ['净余不能抵消没接回的船', '以既定剧中失援后果展示责任；不将它写成玩家战绩奖励。', '收益与损失同页保留'],
      '货损待偿': ['短少要写到具体货项', '展示货损登记与待赔责任的处理入口，不自动从其他用途挪银。', '赔付与净利分别看'],
      '人船保全': ['先保住可以继续走的人船', '保全不等于货物无损，也不等于所有承诺都已兑现。', '下一件事仍需安排']
    },
    accounts: {
      '周转充足': ['每一笔出入都能追到余额', '以实际交易、修船、招募与家书流水核对本次资源栏。', '往航记录不重复入账'],
      '欠款未清': ['净余之外还有尚欠', '显示承诺与待赔用途，未核实金额不编成已发生扣款。', '金额未知就保留待核'],
      '家用被挪': ['用途变了，应当明说', '原定家用投入下一航是剧中责任情境；不偷改当前真实银两或寄件。', '不以未来获利补造已寄'],
      '账目已核': ['核的是这份实际流水', '由每笔余额反推期初，并和现银校验。尚未结清的责任仍另列。', '对账不代表所有人已谅解']
    },
    tutorial: {
      '初次引导': ['从一项动作开始', '先选操船、交易或家书，再按短步骤逐项看；每项能跳到对应界面。', '引导不阻断自由浏览'],
      '可跳过': ['已经会的，就先放下', '所有步骤可直接跳到相关页面，也能在航次中回来查。', '不强制逐页点完'],
      '已学会': ['会了也能回看', '只有实际标记学会的项才留完成标记；未标记的仍照常可读。', '不伪造已经掌握'],
      '随时重看': ['一页手册，按事查找', '交易与寄信保留数额检查，炮击与接舷保留资源和时机提醒。', '文字说明不替代原生操船验证']
    },
    defeat: {
      '玩家操作失败': ['说明最后发生了什么', '把直接原因、当前船况与恢复入口摆在同页，不用一句失败遮住线索。', '不改写固定剧情损失'],
      '可恢复检查点': ['有存档才给读取入口', '按当前会话实际保存的航程显示恢复点，没有则明确说明。', '不制造不存在的检查点'],
      '没有可用存档': ['没有可读的航程', '读取入口停用，保留查看原因与返回主菜单的路。', '空白档不报读取成功'],
      '剧情损失另记': ['有些结果不属于操作重试', '顺生沉失、家变与人物分途沿既定故事留册，不作为玩家处罚。', '从日志回看责任与后续']
    },
    'notification-log': {
      '紧急待办': ['先看会影响开航的事', '按资源、损伤和任务类别筛选当前消息，标记已读仍保留原记录。', '不反复生成同一条提醒'],
      '普通见闻': ['消息仍有来路', '普通见闻与紧急事项分开，可回到消息所指的页面。', '消息人不是系统真值'],
      '已读': ['看过的消息仍能找到', '只列实际标记已读的记录；尚未标记时显示空筛选而非虚构已读。', '已读不等于事项已处理'],
      '相关事项已结束': ['结束状态以实际记录为据', '当前只有消息已读与资源动作记录；没有验收凭据的事项不自动关闭。', '终结状态尚待航次事实支撑']
    }
  };
  function scenarioSurface(id, state, ui) {
    const label = state.previewScenario, entry = lifeScenarios[id]?.[label];
    if (!entry) return '';
    return `<section class="lp-scenario-surface" aria-label="${ui.e(label)}情境说明"><div><span>${ui.e(label)}</span><h2>${entry[0]}</h2><p>${entry[1]}</p></div><aside><strong>${entry[2]}</strong><small>情境仅用于界面审阅，不改写本航真实资源或已发生记录。</small></aside></section>`;
  }

  function portHub(state, ui) {
    const place = state.previewScenario || state.portVisit || '平户邻里';
    const ports = {
      '澳门货栈': ['澳门 · 泊船货栈', 'zheng_a1_s2', '货栈催装，先问掌船人。', '1621 · 剧中早年航程', '黄程的货栈', '验货、吃水与一张船位'],
      '平户邻里': ['平户 · 川内浦', 'zheng_a2_s1', '潮还未退，岸上的事也要办妥。', '第二幕 · 屋檐与远航', '川内浦泊处', '市集、合货与家中来信'],
      '隐蔽锚地': ['闽粤沿海 · 背风锚地', 'zheng_a3_s7', '换来粮与药，也要辨明箱上旧名。', '剧中锚地 · 未指定确切地点', '临时货棚', '补给、封存与原主线索'],
      '港火之后': ['厦门泊区 · 港火之后', 'zheng_a5_s3', '先把人接到岸上，再清点船与货。', '1633 · 港火情境', '临时安置处', '救援、人船点验与修补']
    }, p = ports[place] || ports['平户邻里'];
    const fire = place === '港火之后';
    const stops = [['market','市集','trade','货价、库存与成交',fire?'暂缓开市':'可往来'],['contract-board','货栈','book','托运、护送与交验','先读约定'],['shipyard','船坞','ship','船身、帆索与订造','按损伤报价'],['crew-recruit','茶棚','people','招募与来路消息','逐人问明'],['factions','往来处','flag','势力、凭据与交涉','分清发布者'],['home','家中','letter','灯下的信与未复之事','有信可读']];
    return `${head(ui,p[0],p[2],ui.go('route-plan','筹划下一航','button primary'),p[3])}<div class="lp-port-rebuilt"><section class="lp-port-cinema">${place==='平户邻里'?`<img src="${ui.portImage||'assets/port-hub-v2.png'}" alt="平户港情境，仓房、交易与码头的空间导览">${[['contract-board','货栈',22,42],['market','市集',49,36],['shipyard','码头与整备',83,57]].map(([id,label,x,y])=>`<button class="lp-harbor-hotspot" data-go="${id}" style="--x:${x}%;--y:${y}%"><span></span><strong>${label}</strong></button>`).join('')}`:scene(ui,p[1],p[0])}<div class="lp-port-cinema-caption"><span>${p[4]}</span><strong>${p[5]}</strong><small>港口情境插图 · 入口见下方导览</small></div></section><aside class="lp-port-watch"><div class="lp-watch-heading">${ui.icon('anchor')}<h3>顺风号 · 靠泊中</h3></div>${fact('船体',`${state.hull}% · ${state.hull<85?'有待修处':'可继续整备'}`)}${fact('在船人员',`${state.crew} / ${state.maxCrew} 人`)}${fact('本船米粮',`${stock(state,'grain')} 石`)}${fact('自有银',`${n(state.silver)} 两`)}<h4>先办这两件</h4><ol class="lp-harbor-tasks"><li><span>1</span><div><strong>${fire?'清点受损人船':'核对船况与粮水'}</strong><p>船能否走，先听掌船人说。</p>${ui.go(fire?'battle-damage':'supplies','去核对','text-button')}</div></li><li><span>2</span><div><strong>${fire?'核对尚待交割的货':'把去向写给家中'}</strong><p>${fire?'封存货、托运货与自有货分开。':'归期未定，也不让家中先听旁人说。'}</p>${ui.go(fire?'cargo-hold':'letters','展开记录','text-button')}</div></li></ol></aside></div><nav class="lp-harbor-directory" aria-label="港口据点导览">${stops.map(([id,title,icon,note,status])=>`<div class="lp-harbor-stop">${ui.icon(icon)}<div><strong>${title}</strong><small>${note}</small></div><span>${status}</span>${fire&&id==='market'?'<button class="button" disabled title="港火之后先处理救援与人船点验">暂缓开放</button>':ui.go(id,'进入','button')}</div>`).join('')}</nav><div class="lp-harbor-bottom"><span>${ui.icon('compass')}港内导览：泊处 → 货栈 → 船坞 → 离港筹划</span>${ui.go('intelligence','听消息，先问出处','text-button')}</div>`;
  }

  function market(state, ui) {
    const selected=selectedGood(state), room=cargo(state,ui), filter=state.marketFilter||'all';
    const urgent=scenarioIs(state,'急需补给'), full=scenarioIs(state,'货舱将满');
    let rows=goods.filter(g=>filter==='all'||g.type===filter);
    if(state.marketSort==='price')rows=[...rows].sort((a,b)=>a.buy-b.buy);
    const avail=g=>scenarioIs(state,'库存不足')&&g.id===selected.id?0:marketAvailable(state,g);
    const viewFree=full?Math.min(2,room.free):room.free;
    const allowance=Math.max(0,Math.min(avail(selected),Math.floor(state.silver/selected.buy),Math.floor(viewFree/(cargoWeights[selected.id]||1))));
    return `${head(ui,'平户货市 · 当面验货','报价、余货与本船自有货分开列。交易前，再核对重量与用途。',ui.go('cargo-hold','理清货舱'),'港市与交割')}<div class="lp-market-topline"><span>本港报价 <strong>现银交割</strong></span><span>自有货位 <strong>${room.used} / ${room.capacity}</strong></span><span>可用余位 <strong>${room.free}</strong></span><span>已接委托 <strong>${acceptedContractIds(state).length} 份</strong></span></div><div class="lp-market-layout"><section><div class="toolbar lp-filter">${[['all','全部货物'],['cargo','远运货物'],['supplies','船用补给']].map(([v,l])=>set(ui,'marketFilter',v,l,`button ${filter===v?'active':'subtle'}`)).join('')}${set(ui,'marketSort',state.marketSort==='price'?'name':'price',state.marketSort==='price'?'按原货序':'按买价排列','button subtle')}</div>${urgent?fieldNote('二十日长航程 · 先留口粮',`本船${state.crew}人，按当前估算法建议备粮${Math.ceil(state.crew/8*20)}石；船上实际${stock(state,'grain')}石。`,'warning'):''}${full?fieldNote('封存货占位情境',`另有封存货示例临时占用${Math.max(0,room.free-viewFree)}货位。它不加入自有货库存；买单先留余舱。`,'warning'):''}<div class="lp-table-scroll"><table class="lp-market-table lp-market-detailed"><thead><tr><th>货物 / 来路</th><th>港市余货</th><th>买 / 卖价</th><th>本船自有</th><th>每单位占位</th><th>开单货项</th></tr></thead><tbody>${rows.map(g=>`<tr class="${selected.id===g.id?'selected':''} ${avail(g)===0?'lp-row-unavailable':''}"><td><div class="lp-goods-name">${goodImage(ui,g.id)}<span><strong>${g.name}</strong><small>${g.origin} · ${g.unit}</small></span></div></td><td><strong>${avail(g)} ${g.unit}</strong><small>${avail(g)===0?'暂无余货':g.demand}</small></td><td><strong class="gold">${g.buy}</strong> / ${g.sell}<small>买卖差 ${g.buy-g.sell} 两</small></td><td>${stock(state,g.id)} ${g.unit}<small>${g.type==='supplies'?'船用可支取':'自有可交售'}</small></td><td>${cargoWeights[g.id]} 位</td><td>${set(ui,'selectedGood',g.id,selected.id===g.id?'正在验货':'选取',`button ${selected.id===g.id?'active':'subtle'}`)}</td></tr>`).join('')}</tbody></table></div><div class="lp-market-explanation"><span>本港余货随正常港市成交变化。</span><span>托运封货与关键物件不列入交售。</span></div></section><aside class="lp-good-inspect lp-good-dossier"><div class="lp-good-stage">${goodImage(ui,selected.id,'lp-good-large')}</div><div class="lp-good-title"><h3>${selected.name}</h3>${stamp(selected.type==='supplies'?'船用补给':'远运货物')}</div><p>${selected.note}</p>${fact('买入 / 卖出',`${selected.buy} / ${selected.sell} 两`)}${fact('当前最多可买',`${allowance} ${selected.unit}`)}${fact('约定货位',acceptedContractIds(state).includes('delivery')&&selected.id==='silk'?'托运十二担另列，不可误售':'没有混入托运封货')}${fact('可用银两',`${n(state.silver)} 两`)}${allowance===0?fieldNote('买入暂不可用',avail(selected)===0?'港市已无这项余货，可换选货物或出售自有货。':viewFree< (cargoWeights[selected.id]||1)?'没有足够余舱，请先理货。':'现银不足购买一单位。','warning'):''}${ui.go('trade-order',`核对${selected.name}买卖单`,'button primary')}${action(ui,'buy','按现价买一单位','button',{item:selected.id,price:selected.buy,market:'port'},allowance<1)}${ui.go('black-market','查看隐蔽锚地的另一份报价','text-button')}</aside></div>`;
  }

  function tradeOrder(state, ui) {
    const g=selectedGood(state),mode=state.tradeMode||'buy',price=mode==='buy'?g.buy:g.sell,room=cargo(state,ui),weight=cargoWeights[g.id]||1;
    const bySilver=Math.floor(Number(state.silver)/price),byRoom=Math.floor(room.free/weight),byMarket=marketAvailable(state,g);
    const unavailable=mode==='buy'&&(scenarioIs(state,'银两不足')||scenarioIs(state,'容量不足'));
    const max=mode==='buy'?Math.max(0,Math.min(bySilver,byRoom,byMarket)):stock(state,g.id);
    const qty=mode==='buy'&&scenarioIs(state,'银两不足')?bySilver+1:1;
    const total=price*qty,after=Number(state.silver)+(mode==='buy'?-total:total);
    const transaction=(state.transactions||[]).find(t=>t.time==='刚刚'&&['交易','贸易'].includes(t.category));
    return `${head(ui,'货物成交清单',`${g.origin} · ${g.name} · 核对之后再交割`,ui.go('market','换选货物'),'货单与实数')}<div class="lp-order-layout"><section class="lp-order-object lp-order-inspection">${goodImage(ui,g.id,'lp-order-good')}<div><span>${stamp(mode==='buy'?'向货行买入':'交售本船自有货')}</span><h3>${g.name}</h3><p>${g.note}</p></div><dl class="lp-goods-provenance"><dt>货物来源</dt><dd>${g.origin}</dd><dt>计量</dt><dd>每${g.unit}占 ${weight} 货位</dd><dt>本船自有</dt><dd>${stock(state,g.id)} ${g.unit}</dd><dt>封存与托运</dt><dd>本单不处置</dd></dl></section><section class="paper lp-order-paper"><div class="lp-order-seal">验货</div><div class="toolbar">${set(ui,'tradeMode','buy','买入',`button ${mode==='buy'?'active':''}`)}${set(ui,'tradeMode','sell','卖出',`button ${mode==='sell'?'active':''}`)}</div><h3>${mode==='buy'?'向货行买入':'向货行交售'}${g.name}</h3><div class="lp-order-limits">${fact('每'+g.unit+'单价',`${price} 两`)}${fact('本次最大数量',`${max} ${g.unit}`)}${mode==='buy'?`<p class="small">港市 ${byMarket} · 预算 ${bySilver} · 余舱 ${byRoom}，取三者最小值。</p>`:''}</div><label class="field" for="trade-quantity">交割数量（${g.unit}）<input id="trade-quantity" type="number" min="1" max="${Math.max(1,max)}" step="1" value="${qty}" inputmode="numeric" data-unit-price="${price}" data-trade-mode="${mode}" data-unit-weight="${weight}" data-cargo-used="${room.used}"></label><div class="lp-order-total"><span>${mode==='buy'?'应付价银':'可收价银'}</span><strong><output id="trade-total">${n(total)}</output> <small>两</small></strong></div><div class="lp-order-final">${fact('额外费用','本单无另收费用')}<div class="lp-fact"><span>成交后银两</span><strong><output id="trade-balance">${n(after)}</output> 两</strong></div><div class="lp-fact"><span>成交后占舱</span><strong><output id="trade-cargo-after">${room.used+(mode==='buy'?1:-1)*qty*weight}</output> / ${room.capacity}</strong></div></div>${unavailable?fieldNote('本情境不可确认',scenarioIs(state,'银两不足')?`示例订单超出预算 ${Math.max(0,total-state.silver)} 两；减少数量后再核对。`:'剩余货位在本情境中已预留给封存与救援，不再加入新货。','warning'):max<1?fieldNote('当前不可成交',mode==='sell'?'本船没有可交售的这项自有货。':byMarket<1?'本港这项货物暂无余货。':bySilver<1?'现银不足购买一单位。':'余舱不足容纳一单位，请先理货。','warning'):''}${action(ui,mode,`核对无误，确认${mode==='buy'?'买入':'卖出'}`,'button primary',{item:g.id,price,market:'port'},max<1||unavailable)}<p class="small lp-order-foot">成交后货物、现银、港市余货与账房流水一同更新；不能出售他人托付的封货。</p></section></div>${scenarioIs(state,'成交完成')||transaction?`<section class="lp-trade-receipt"><div>${ui.icon('check')}<span>成交凭据</span></div>${transaction?`<strong>${ui.e(transaction.title)}</strong><span>${Number(transaction.delta)>0?'+':''}${n(transaction.delta)} 两 · 该笔后余额 ${n(transaction.balance)} 两</span>${ui.go('accounts','到账房逐笔核对','button')}`:`<p>当前还没有本次成交记录。完成一笔买卖后，这里会显示实际金额与余额。</p>`}</section>`:''}`;
  }

  function contractBoard(state, ui) {
    const accepted=acceptedContractIds(state),filter=state.contractFilter||'all',selected=state.selectedContract||'escort';
    const rows=Object.entries(contracts).filter(([id])=>filter==='all'||filter==='ready'&&!accepted.includes(id)||filter==='accepted'&&accepted.includes(id)||filter==='pending'&&state.contractDeliveries?.[id]==='pending');
    const c=contracts[selected]||contracts.escort,disputed=scenarioIs(state,'有争议');
    return `${head(ui,'货栈委托','交付地点、接应责任与到期条件先于报酬；每一份约都能留在日志里。',ui.go('quest-journal','查看已接事务'),'航次差事')}<div class="lp-board-summary"><span>${Object.keys(contracts).length} 份在板</span><span>${accepted.length} 份已接</span><span>${Object.values(state.contractDeliveries||{}).filter(x=>x==='pending').length} 份待验</span><small>完约报酬须验收后另结</small></div><div class="toolbar lp-filter">${[['all','全部差事'],['ready','尚可承接'],['accepted','已接在册'],['pending','待交验']].map(([v,l])=>set(ui,'contractFilter',v,l,`button ${filter===v?'active':''}`)).join('')}</div>${disputed?`<section class="lp-dispute-register"><div>${stamp('代运货物 · 只读争议样例','warning')}<h3>十二担生丝中，两担封记不合</h3><p>十担封记可核；两担暂存原箱，装货方与收货方各留说明。未验清前不结报酬，也不把货卖入自有清单。</p></div><dl><dt>可先核交</dt><dd>10 担</dd><dt>暂存待辨</dt><dd>2 担</dd><dt>报酬</dt><dd>280 两暂缓</dd></dl><button class="button" disabled>争议未明，不能结清</button>${ui.go('contract-detail','逐项看交验凭据','button')}</section>`:''}<div class="lp-contract-board"><section class="lp-contract-posts">${rows.length?rows.map(([id,item])=>`<article class="lp-contract-post ${selected===id?'chosen':''}"><div class="lp-post-top"><span>${item.client} · ${item.days}</span>${stamp(state.contractDeliveries?.[id]==='pending'?'已提交待验':accepted.includes(id)?'已承接':'尚可承接')}</div><h3>${item.title}</h3><div class="lp-contract-destinations"><span>从 ${item.route[0]}</span>${ui.icon('arrow')}<strong>${item.route.at(-1)}</strong></div><p>${item.risk} · ${item.cargo}</p><div class="lp-post-bottom"><span>完约报酬 <strong>${item.reward} 两</strong></span>${set(ui,'selectedContract',id,selected===id?'案头正在细读':'取下细读',`button ${selected===id?'active':''}`)}</div></article>`).join(''):empty(ui,filter==='pending'?'还没有待验委托':'这一册目前没有条目',filter==='pending'?'承接后核对交验事项，再提交待验；提交不会自动领银。':'可先在“尚可承接”中逐条读约。',null,'')}</section><aside class="lp-contract-preview"><span class="gold">案头这份 · ${accepted.includes(selected)?'已承接':'尚未签下'}</span><h3>${c.title}</h3><p>${c.note}</p>${fact('交付给',c.client)}${fact('预计在航',c.days)}${fact('货位条件',c.cargo)}${fact('特别责任',c.risk)}${ui.go('contract-detail','展开契纸与交验清单','button primary')}${ui.go('destination-detail','核对目的港条件','text-button')}<p class="small muted">口头追加的接应或担损，须另记双方是否同意，不能悄悄并入原约。</p></aside></div>`;
  }

  function contractDetail(state, ui) {
    const id=state.selectedContract||'escort',c=contracts[id]||contracts.escort,accepted=acceptedContractIds(state).includes(id),pending=state.contractDeliveries?.[id]==='pending',room=cargo(state,ui);
    const needed=id==='delivery'?12:id==='salvage'?8:0;
    const loss=scenarioIs(state,'欠损未清');
    const enough=room.free>=needed&&(id!=='escort'||Number(state.hull)>=60&&Number(state.crew)>=20)&&!scenarioIs(state,'条件不足')&&!loss;
    const evidence=[['manifest',id==='escort'?'同航船数与到港见证':'货物清单与封记'],['identity','双方交接人与来路'],['loss','短少、损伤与追加约定']];
    const allChecked=evidence.every(([key])=>Boolean(state[`contract-evidence-${id}-${key}`]));
    return `${head(ui,'约定与交验',`${c.client} · ${c.title}`,ui.go('contract-board','返回委托板'),'逐条读约')}<div class="wide-split lp-contract-detail"><article class="paper lp-deed"><div class="lp-deed-heading"><span>双方留照</span><strong>本航次约</strong><span>${pending?'待对方验明':accepted?'已承接留册':'待双方签定'}</span></div><h2>${c.title}</h2><p class="lp-deed-lead">${c.note}</p>${route(c.route)}<ol class="lp-terms">${c.terms.map(t=>`<li>${t}</li>`).join('')}</ol><div class="lp-deed-clauses"><div><h3>交验的凭据</h3><p>${id==='escort'?'同航船平安抵达的在场见证、原约接应信号与船数。':id==='delivery'?'装货清单、原箱封记与交货一方的点验记录。':'原主提供的箱印、封条和实际找回的货物。'}</p></div><div><h3>有损怎样记</h3><p>先写短少和受损事实，再辨各方责任。争议货另封存，不以一句抵港抹去原来的名字。</p></div></div><div class="lp-deed-sign"><span>委托方：${c.client}</span><span>承接方：一官船队</span></div><div class="lp-deed-status">${stamp(pending?'交验已提交':accepted?'约已入册':'尚待签下')}</div></article><aside class="lp-terms-aside">${ui.metric('完约后报酬',n(c.reward),'两')}${fact('当前余舱',`${room.free} / ${room.capacity} 位`)}${fact('本约至少预留',needed?`${needed} 位`:'不占自有货位')}${fact('接应人船',id==='escort'?`船体${state.hull}% · 船员${state.crew}人`:'交接人须能说明来路')}${!accepted?`${!enough?fieldNote('条件还不能答应',scenarioIs(state,'条件不足')?'本情境展示接应船或货位尚未落实，先回整备处。':room.free<needed?'余舱不足预留本约货位。':'护送至少需要船体60%、20名在船人员。','warning'):''}${action(ui,'accept-contract','读明责任，承接此约','button primary',{item:id},!enough)}`:`<section class="lp-contract-checks"><h3>交验前逐项核对</h3>${evidence.map(([key,label])=>ui.action('toggle',`${state[`contract-evidence-${id}-${key}`]?'☑':'□'} ${label}`,`lp-check-button ${state[`contract-evidence-${id}-${key}`]?'checked':''}`,{key:`contract-evidence-${id}-${key}`})).join('')}${action(ui,'deliver-contract',pending?'已提交，等对方验明':'提交交验，登记待验','button primary',{item:id},pending||!allChecked)}<p class="small muted">${pending?'已登记待验，不会重复提交或自动发报酬。':allChecked?'资料已核对；提交之后仍须对方验明。':'三项资料核对完毕后才开放提交。此处不代造航行或验收结果。'}</p></section>`}${loss?`<section class="lp-loss-register"><h3>短损单 · 只读样例</h3>${fact('原约封货','12 担')}${fact('可交封货','10 担')}${fact('另存待核','2 担')}${fact('报酬处置','280 两暂缓，未入现银')}<p>待补装货封记、受潮见证与双方担责说明。赔付额尚未验定，不以预计报酬自动冲平。</p><button class="button" disabled>短损未核，不能结清</button></section>`:''}${ui.go('quest-journal','回看已接事务','text-button')}${ui.go('route-plan','检查航路与整备','button')}</aside></div>`;
  }

  function blackMarket(state, ui) {
    const mode=state.hiddenFilter||'all',refused=scenarioIs(state,'买主拒收'),pursued=scenarioIs(state,'有人追索'),uncertain=scenarioIs(state,'来路待辨');
    const offers=[{id:'spices',action:'buy',name:'散包香料',price:62,source:'卖方能说明转手来路，可当面验货',status:'可问价'}, {id:'silk',action:'sell',name:'本船自有生丝',price:34,source:'以自有清单交售，不接他人托运封货',status:uncertain?'归属待核 · 暂停交售':'折价收购'}, {id:'grain',action:'buy',name:'补入米粮',price:18,source:'先供船上人吃饭，别把全程余粮卖光',status:'船用补给'}].filter(x=>mode==='all'||mode==='sell'&&x.action==='sell'||mode==='buy'&&x.action==='buy');
    const room=cargo(state,ui);
    return `${head(ui,'背风锚地的另一份价','能换到粮与货，也可能听到有人追问箱子原来的名字。',ui.go('market','回到正常港市'),'货物、来路与风险')}<div class="lp-hidden-market"><aside class="lp-hidden-image">${scene(ui,'zheng_a3_s7','锚地分货与补给')}<div><span>${stamp(pursued?'有人追问去向':'先辨来处，再谈价')}</span><h3>不是每一箱都能拿来卖</h3><p>本船自有清单、托运封货与争议货分别摆放。价银再急，也不把别人名字抹去。</p>${ui.go('intelligence','核对谁在追问','text-button')}</div></aside><section><div class="toolbar lp-filter">${[['all','全部报价'],['sell','交售自有货'],['buy','换取船用物资']].map(([v,l])=>set(ui,'hiddenFilter',v,l,`button ${mode===v?'active':''}`)).join('')}</div>${offers.map(o=>{const has=o.action==='buy'?state.silver>=o.price&&room.free>=cargoWeights[o.id]:stock(state,o.id)>0;return `<article class="lp-exchange-row">${goodImage(ui,o.id)}<div><span class="small gold">${o.status}</span><h3>${o.name}</h3><p>${o.source}</p><small>本船自有 ${stock(state,o.id)} 单位 · 港市另一报价 ${o.action==='buy'?goods.find(g=>g.id===o.id).buy:goods.find(g=>g.id===o.id).sell} 两</small></div><div class="lp-hidden-quote"><strong>${o.price} 两 / 单位</strong>${action(ui,o.action,o.action==='buy'?'按此价买一单位':'按此价卖一单位','button',{item:o.id,price:o.price,market:'hidden'},!has||refused||uncertain&&o.action==='sell')}${!has||refused||uncertain&&o.action==='sell'?`<small>${refused?'买主本次拒收／停议':uncertain&&o.action==='sell'?'先核货主与封记，暂不交售':o.action==='sell'?'无可交售自有货':state.silver<o.price?'现银不足':'余舱不足'}</small>`:''}</div></article>`}).join('')}${uncertain?`<section class="lp-provenance-check"><h3>这批货还缺两份能对上的说明</h3><ul><li><strong>货主名字：</strong>货单与箱印各有旧记，尚未一致。</li><li><strong>转手来路：</strong>卖方只能口述，缺装货方的在场见证。</li><li><strong>可以先办：</strong>买入米粮照应在船人员；争议封货继续隔开存放。</li></ul></section>`:''}<div class="lp-sealed-cargo"><span class="lp-seal">待辨</span><div><h3>红封混载货箱 · 不列成交</h3><p>封记并不一致，另有商户提出原主线索。登记封存与辨认，不能先折价卖掉再称已经结清。</p><div class="toolbar">${ui.action('toggle',state.disputedCargoNoted?'封存事项已记下':'记下：争议货暂存待辨','button',{key:'disputedCargoNoted'})}${ui.go('intelligence','查原主线索','text-button')}</div></div></div>${pursued?fieldNote('私人追索风险','追问者是谁、根据什么认货尚待核实。这不是官府公文，不能套作公权授权。','warning'):''}</section></div>`;
  }

  function supplies(state, ui) {
    const days=Number(state.provisionDays||10),room=cargo(state,ui),grainTarget=Math.ceil(Number(state.crew)/8*days),targets={grain:grainTarget,wood:20,iron:12};
    const quantities=goods.filter(g=>g.type==='supplies'),missing=quantities.reduce((sum,g)=>sum+Math.max(0,targets[g.id]-stock(state,g.id))*g.buy,0);
    const conflict=scenarioIs(state,'容量冲突');
    return `${head(ui,'离岸前的补给单','按人数与航程留出余量。粮、木与铁可以在此采购；淡水、药材仍需现场核验。',ui.go('route-plan','回看计划航路'),'粮水与余舱')}<div class="lp-provision-route"><div><span>计划在航</span><div class="toolbar">${[6,10,20,40,60].map(d=>set(ui,'provisionDays',d,`${d}日`,`button ${days===d?'active':''}`)).join('')}</div></div><div>${fact('在船人数',`${state.crew} 人`)}${fact('货位已用',`${room.used} / ${room.capacity}`)}${fact('按建议补齐',`${n(missing)} 两`)}</div></div><div class="lp-provision-layout"><section><div class="lp-provision-columns"><span>物资 / 用处</span><span>现有 / 建议</span><span>缺口与价银</span></div>${quantities.map(g=>{const current=stock(state,g.id),target=targets[g.id],gap=Math.max(0,target-current),weight=cargoWeights[g.id],max=Math.min(marketAvailable(state,g),Math.floor(state.silver/g.buy),Math.floor(room.free/weight));return `<article class="lp-provision-item">${goodImage(ui,g.id,'lp-provision-image')}<div><h3>${g.name}</h3><p>${g.note}</p><span>${current} / ${target} ${g.unit} ${stamp(gap?`尚缺${gap}${g.unit}`:'已有余量',gap?'warning':'')}</span><div class="lp-provision-meter"><i style="width:${Math.min(100,current/Math.max(1,target)*100)}%"></i></div></div><div><strong>${g.buy} 两 / ${g.unit}</strong><span class="small muted">${weight}货位 / 单位</span>${action(ui,'buy',`补入一${g.unit}`,'button',{item:g.id,price:g.buy,market:'port'},max<1||conflict)}${max<1||conflict?`<small>${conflict?'预留货位冲突':state.silver<g.buy?'现银不足':room.free<weight?'余舱不足':'港市缺货'}</small>`:''}</div></article>`}).join('')}<div class="lp-provision-unverified"><div><strong>淡水桶</strong><span>${scenarioIs(state,'水量不足')?'未达核验条件':'待逐桶核验'}</span><p>没有已核水量记录时，不按米粮天数替代淡水续航。</p>${ui.action('toggle',state.waterChecked?'已记下逐桶检查':'记录：淡水桶已逐项检查','button',{key:'waterChecked'})}</div><div><strong>药材与救援物资</strong><span>另行点验</span><p>在船员与损伤页核对需求，不在货价表中凭空增加药量。</p>${ui.go('crew-roster','核对人员需求','text-button')}</div></div></section><aside class="lp-provision-check panel"><h3>离岸前最后一遍</h3><ul class="lp-check-list"><li><span>米粮</span><strong>${stock(state,'grain')>=grainTarget?'已达所选航日建议':'尚有建议缺口'}</strong></li><li><span>淡水</span><strong>${state.waterChecked?'已记逐桶检查，水量仍按现场记录':'尚未记下逐桶检查'}</strong></li><li><span>船体</span><strong>${state.hull}% · ${state.hull<85?'先看待修处':'可继续整备'}</strong></li><li><span>接应约定</span><strong>${acceptedContractIds(state).length}份已接，逐条回看</strong></li></ul>${missing>state.silver||scenarioIs(state,'超出预算')?fieldNote('先处理预算缺口',`补齐建议需${n(missing)}两，当前可支${n(state.silver)}两。可缩短航日或分批补入，不能负银采购。`,'warning'):''}${ui.go('ship-repair','处理船体待修处','button')}${ui.go('contract-board','检查接应约定','text-button')}<p class="small muted">这是一份备航建议，不是必定安全抵达的保证。</p></aside></div>`;
  }

  function questJournal(state, ui) {
    const filter=state.journalFilter||'all',accepted=acceptedContractIds(state),sent=sentRecords(state),pending=Object.entries(state.contractDeliveries||{}).filter(([,s])=>s==='pending');
    const tabs=[['all','全部未竟',3+accepted.length],['main','当前主线',1],['contracts','航次委托',accepted.length],['promise','承诺与家事',2],['done','已发生记录',sent.length+pending.length]];
    const mainEntry=`<article class="lp-journal-feature"><div class="lp-journal-entry-meta">${stamp(state.questAccepted?'已追踪':'可追踪')}<span>第二幕 · 1624 · 大员附近</span></div><h2>他没有回去的那一航</h2><p>福松出生的喜讯已经到船上。下一航已经应下，回信里还需把自己的安排写明。</p>${route(['读完平户来信','核对已答应的航次','写明自己的安排'])}<div class="lp-journal-next"><span>下一步</span><strong>${sent.length?'等回音，继续核对原定家用':'在灯下写回信，分别记下家用'}</strong></div><div class="toolbar">${ui.go('quest-detail','目标、代价与凭据','button primary')}${ui.go('send-letter-remittance','写明安排','button')}</div></article>`;
    const contractEntries=accepted.map(id=>`<article class="lp-promise-entry"><div class="lp-journal-entry-meta">${stamp(state.contractDeliveries?.[id]==='pending'?'已提交待验':'已接在册')}<span>${contracts[id].client}</span></div><h3>${contracts[id].title}</h3><p>${contracts[id].route.join(' → ')} · ${contracts[id].risk}</p><div class="toolbar">${set(ui,'selectedContract',id,state.selectedContract===id?'此约正在案头':'取此约到案头','button')}${state.selectedContract===id?ui.go('contract-detail','展开交验事项','text-button'):''}</div></article>`).join('');
    const promises=`<article class="lp-promise-entry"><span>给家中 · 一官须答复</span><h3>${sent.some(x=>Number(x.amount)>0)?'家用已托寄，还等回音':'原定家用，仍须另行安排'}</h3><p>银的用途与归期分别说明。写好不等于托寄，托寄也不等于已经收到。</p>${ui.go('send-letter-remittance','答复与汇银','button')}${ui.go('accounts','看银的去向','text-button')}</article><article class="lp-promise-entry"><span>同船的人 · 出航前</span><h3>听完阿旺的船况与吃水意见</h3><p>在答应船期之前，让掌船人的判断真正进入决定，不用事后的盈利替代事先商量。</p>${ui.go('relationships','相关人的诉求与旧事','text-button')}</article>`;
    const completed=[...sent.map(x=>`<article class="lp-completed-entry">${ui.icon('check')}<div><h3>${ui.e(x.title)}</h3><p>家信已托寄，随信家用${n(x.amount)}两；收到与否仍待回音。</p></div>${ui.go('letters','看寄件','button')}</article>`),...pending.map(([id])=>`<article class="lp-completed-entry">${ui.icon('check')}<div><h3>${contracts[id]?.title||id} · 交验已提交</h3><p>只完成了提交，委托仍待验收，不列作完约收入。</p></div>${ui.go('contract-board','看待验册','button')}</article>`)];
    return `${head(ui,'航海日志','目标、承诺、委托与实际记录分册；每件事都能追到对象与下一步。',ui.go('chronicle','回看生涯编年'),'留在册中的事')}<div class="lp-journal-layout"><aside class="lp-journal-index">${tabs.map(([id,label,count])=>set(ui,'journalFilter',id,`${label}<span>${count}</span>`,`lp-journal-tab ${filter===id?'active':''}`)).join('')}${ui.go('intelligence','消息与证据','lp-journal-tab')}${ui.go('notification-log','最近的变更','lp-journal-tab')}<div class="lp-journal-legend"><span>追踪 ≠ 完成</span><span>提交 ≠ 验收</span><span>托寄 ≠ 收到</span></div></aside><section class="lp-journal-pages">${['all','main'].includes(filter)?mainEntry:''}${['all','promise'].includes(filter)?promises:''}${['all','contracts'].includes(filter)?contractEntries||empty(ui,'还没有承接的航次委托','先到货栈逐条读约，接受后才会留入这本册。','contract-board','去委托板'):''}${filter==='done'?completed.join('')||empty(ui,'还没有本次已发生的记录','寄出一封家信或提交一份已接委托后，会留下实际凭据。','letters','先看家书'):''}</section></div>`;
  }

  function questDetail(state, ui) {
    const phase=state.previewScenario||'准备执行',records=sentRecords(state),done=Boolean(state.letterSent||records.length),progress=phase==='目标进行中',cost=phase==='完成有代价',fixed=phase==='固定结果';
    const steps=[['已知','福松在平户出生，母子平安','家信已经收到，另有回船可捎人或小包。'],['已定','一官应下了下一航','离开眼前的差事不是没有路；留下也须认是自己作的决定。'],[done||cost?'托寄':progress?'正在写':'待办','向家中写明已经作出的安排',done?'家信已经交托。收到与否，要等返船带回消息。':cost?'完成托寄的界面样例：安排已写明，家用与信费分开记；仍未收到家中回音。':progress?'已把此事留在日志，回信草稿尚未封好；下一步核对托话人与费用。':'归期尚无定日，不再用一笔未来收益替代说明。']];
    return `${head(ui,'他没有回去的那一航','第二幕 · 1624 · 大员附近船上',ui.go('quest-journal','回到日志'))}<div class="lp-quest-layout"><div class="lp-quest-image">${scene(ui,'zheng_a2_s4','一官在舱中重读家信')}<blockquote>“几个月孩子认谁，是岸上的事。”<cite>阿旺</cite></blockquote></div><section class="lp-quest-objectives"><div class="lp-objective-progress"><strong>${fixed?'正线结果留档':done||cost?'3 / 3 项已留下凭据':progress?'2 / 3 项已核对':'2 / 3 项已知'}</strong>${stamp(fixed?'不可改写':done||cost?'托寄后仍待回音':progress?'目标已追踪':'准备答复')}</div><h3>${fixed?'这一场已经作出的决定':'眼前要办的事'}</h3><ol class="lp-objectives">${steps.map(([status,title,body],i)=>`<li class="${i===2&&progress?'lp-objective-current':''}"><span class="${i<2||done||cost?'lp-step-done':''}">${status}</span><div><strong>${title}</strong><p>${body}</p></div></li>`).join('')}</ol>${fixed?`<section class="lp-fixed-outcome"><h3>可行的回船没有被选择</h3>${route(['回平户船位可用','一官应下新航','没有同行回家','后来书信不能补成团聚'])}<p>此处沿 a2_s4 既定正线展示。不开放“赶上回船”的改史选择，也不把未回去归为无船可回。</p><button class="button" disabled>本场决定已记入生涯</button>${ui.go('chronicle','回看前因与后续','text-button')}</section>`:`<div class="lp-quest-cost"><h3>${cost?'事情做完，代价仍在':'这一程的代价'}</h3><p>接下航次，便会错过眼前可行的回家机会。寄回银两不会让未能团聚的日子消失。</p>${cost?`<dl class="lp-evidence-pairs"><dt>完成了什么</dt><dd>说明自己的安排，留下托寄凭据</dd><dt>没有因此完成</dt><dd>回到平户、家中收到、原定家用全部落实</dd></dl>`:''}</div><div class="toolbar">${action(ui,'accept-quest',state.questAccepted||progress?'当前目标已追踪':'追踪这件事','button primary',{item:'zheng_a2_s4'},state.questAccepted||progress)}${ui.go(cost||done?'letters':'send-letter-remittance',cost||done?'回看信与未等到的回音':progress?'继续写尚未封好的回信':'去写这封回信','button')}</div>`}</section></div>`;
  }

  function chronicle(state, ui) {
    const entries=[
      ['1621','澳门起步','story','剧中起点','一官初到澳门货栈，翻话、抢潮与失货构成早年的原创冒险，不据此补定未核行程。','zheng_a1_s1'],
      ['约1622／1623','两个人的屋檐','cross','跨年与文学重建','早年在日编年保留范围；相识、小屋与私下谈话均是剧情演绎。','zheng_a2_s2'],
      ['1624','福松生于平户','history','历史节点','出生为这一年的骨架。家信、可返船位与一官的具体取舍来自本剧。','zheng_a2_s4'],
      ['1625','率两艘唐船会合的锚点','history','研究锚点','相关研究提供两船行动的锚点，不把剧中的雾航、船名与交割细节当成史料原文。','zheng_a3_s1'],
      ['1628','受抚，授游击','history','历史节点','官身与报效责任改变通路与旧盟关系。现场对白与具体名册为创作。','zheng_a4_s4'],
      ['1629','湾口抗掠的具体战事','story','原创航次','无名湾口、混合掠夺团伙、人质与中止火攻均为原创，不能据图文主张真实郑氏抗倭战绩。','zheng_a4_s7'],
      ['1630','福松赴明','history','历史节点','由亲属照护赴明，母亲未在这一程同行；送行的玩物、小碗和对白为剧中私事。','zheng_a5_s1'],
      ['1633','料罗湾之战','history','历史节点','海战为历史骨架；火船上的具体人物、接应约定与现场对白是创作。','zheng_a5_s4'],
      ['1634','舍去主桅保人船','story','原创短航','父子沿海出航与折桅全为文学铺垫，不宣称已核郑氏携子遇此风暴。','zheng_a5_s7'],
      ['1635—1645','另一岸的十五年','cross','跨年概括','两岸船信仍通，家人的人生态度随时间变化；不伪造传世家信或确切托寄日。','zheng_a6_s1'],
      ['1645—1646','团聚，又分途','history','历史节点与私事分列','田川氏赴泉州，森得赐姓、名成功；翌年芝龙降清、成功不从。家中场面为文学演绎。','zheng_a6_s2']
    ];
    const kind=state.chronicleKind||'all',year=state.chronicleYear||'all',rows=entries.filter(e=>(kind==='all'||e[2]===kind)&&(year==='all'||e[0].includes(year)));
    return `${head(ui,'海上编年','史实给出骨架，剧中人物还要过完其中的日子。年份范围与创作边界分别标明。',ui.go('history-notes','查阅史料说明'),'1621—1646')}<div class="lp-chronicle-controls"><div class="toolbar">${[['all','全部节点'],['history','历史骨架'],['cross','跨年概括'],['story','原创航次']].map(([v,l])=>set(ui,'chronicleKind',v,l,`button ${kind===v?'active':''}`)).join('')}</div><div class="toolbar">${[['all','全部年份'],['1624','1624'],['1628','1628'],['1630','1630'],['1633','1633'],['1645','1645之后']].map(([v,l])=>set(ui,'chronicleYear',v,l,`button subtle ${year===v?'active':''}`)).join('')}</div></div><ol class="lp-chronicle">${rows.length?rows.map(([date,title,type,label,text,image])=>`<li><div class="lp-chronicle-date">${date}<span>${label}</span></div><div class="lp-chronicle-image">${scene(ui,image,title)}</div><div>${stamp(type==='story'?'具体事件为创作':type==='cross'?'保留时间范围':'史实与私事分列')}<h3>${title}</h3><p>${text}</p>${ui.go('chapter-select','回章场看相关生涯','text-button')}</div></li>`).join(''):empty(ui,'这组筛选没有相符节点','可以换一年或恢复全部节点；不为填满一页而补造历史事件。',null,'')}</ol>`;
  }

  function intelligence(state, ui) {
    const filter=state.intelFilter||'all',sea=state.intelSea||'all';
    let items=intel.map((x,index)=>({...x,sea:index===0?'taiwan':index===1?'hirado':'fujian'}));
    if(scenarioIs(state,'已证伪'))items.push({id:'preview-disproved',category:'disproved',sea:'fujian',title:'旧传：一面熟旗便可免验',source:'情境示例 · 在场核验后否定',age:'保留旧记录',status:'已否定，不可作行动依据',place:'沿海水路',content:'熟悉旗色不能证明船、货与委托关系。这一示例用于展示消息被否定后的留档方式，不新增一场已证历史遭遇。',limit:'不能继续据旧说法承诺安全通行。',action:'sea-permits',label:'重新核对凭据'});
    if(scenarioIs(state,'已过时'))items=items.map(x=>x.id==='wind'?{...x,category:'expired',status:'风信已过时',age:'两日前的风信',limit:'不能用旧云势决定今天的离港时辰。'}:x);
    const rows=items.filter(x=>(filter==='all'||x.category===filter)&&(sea==='all'||x.sea===sea));
    const selected=rows.find(x=>x.id===state.selectedIntel)||rows[0];
    return `${head(ui,'情报与航路见闻','出处、时间、可信范围与下一次该问谁，留在同一份记录里。',ui.go('sea-chart','对照海图'),'据谁所知')}<div class="lp-intel-controls"><div class="toolbar">${[['all','全部'],['confirmed','已有核实'],['unverified','待核消息'],['expired','过时留档'],['disproved','已否定']].map(([v,l])=>set(ui,'intelFilter',v,l,`button ${filter===v?'active':''}`)).join('')}</div><div class="toolbar">${[['all','所有海域'],['hirado','港口与风候'],['taiwan','大员泊处'],['fujian','福建沿海']].map(([v,l])=>set(ui,'intelSea',v,l,`button subtle ${sea===v?'active':''}`)).join('')}</div></div><div class="lp-intel-layout"><section class="lp-intel-list">${rows.length?rows.map(x=>`<button type="button" class="lp-intel-entry ${selected?.id===x.id?'selected':''}" data-action="set" data-key="selectedIntel" data-value="${x.id}"><div class="lp-intel-entry-top"><span class="lp-intel-status">${x.status}</span><small>${x.age}</small></div><h3>${x.title}</h3><span>${x.source}</span><small>${x.place}${state[`intel-follow-${x.id}`]?' · 已记待查':''}</small></button>`).join(''):empty(ui,'此筛选中没有消息','换一个海域或可信状态；没有核验记录时，不会编出一条已证事实。',null,'')}</section>${selected?`<article class="lp-intel-reader"><div class="lp-intel-reader-heading">${stamp(selected.status,selected.category==='confirmed'?'':'warning')}<span>${selected.age}</span></div><h2>${selected.title}</h2><p class="lp-intel-report">${selected.content}</p><dl class="lp-source-dossier"><dt>消息从谁来</dt><dd>${selected.source}</dd><dt>核实到哪里</dt><dd>${selected.place}</dd><dt>还不能据此断定</dt><dd>${selected.limit}</dd><dt>下一次核对</dt><dd>${selected.category==='expired'?'离港前重新看风候':selected.category==='confirmed'?'起锚前再问船位是否仍在':'逐箱辨记，并听另一方的说法'}</dd></dl><div class="toolbar">${ui.go(selected.action,selected.label,'button primary')}${ui.action('toggle',state[`intel-follow-${selected.id}`]?'已记待查，再点取消':'将此条记为待查','button',{key:`intel-follow-${selected.id}`})}</div><p class="small muted">标记待查只留下你的追问，不把消息升级为已核实。</p></article>`:'<article class="lp-intel-reader"><h2>先选一条有出处的消息</h2><p class="muted">尚无相符记录。旧消息仍在原来的可信状态中保留。</p></article>'}</div>`;
  }

  function relationships(state, ui) {
    const people=[
      {id:'tagawa',name:'田川氏',kind:'family',relation:'家中与海上',wish:'先知道你的去向，而不是从旁人处先听见。',owed:'归期与原定家用各须答复。',support:'两个人各退一步，住进平户小屋；留岸的人也有自己的生活。',boundary:'寄钱不能替她决定怎样度过等待。',scene:'zheng_a2_s3',event:'行李里的刀与没有说完的风险',target:'letters',label:'读她的来信'},
      {id:'awang',name:'阿旺',kind:'crew',relation:'掌船的老伙伴',wish:'船况、吃水与阿禾的安危，需要在应下船期之前被听见。',owed:'不能让受伤的掌船人替抢潮的决定受罚。',support:'他把多年掌船经验放在这条船上，也有想回家的时候。',boundary:'同船多年，不等于永远替船长答应。',scene:'zheng_a1_s4',event:'养伤处的责任与一张被撤去的铺位',target:'crew-detail',label:'查看他的打算'},
      {id:'duqi',name:'杜七',kind:'ally',relation:'各有船的盟友',wish:'各自能作主的地位、说定的分利与不能擅撤的接应。',owed:'他曾舍货换人；损船与回援约定不能只在自己获救时算数。',support:'船、熟水手与火器各有投入，双方的合作并非全盘继承。',boundary:'银和一面旗，不能买回同样的地位。',scene:'zheng_a4_s5',event:'门槛上，旧伙伴没有被一顿饭招回',target:'diplomacy',label:'核对具体盟约'},
      {id:'chentian',name:'陈添',kind:'crew',relation:'账与话都经他的手',wish:'把数与话记清，知道哪些是已经决定的安排。',owed:'主角亲自作出的决定，不能事后全归成传话人的责任。',support:'记账、托话与校正读音，是他具体能帮的事。',boundary:'代为传话，不等于有权替所有人同意。',scene:'zheng_a2_s5',event:'红线袋收起，家用被投入下一航',target:'accounts',label:'看银的真实去向'}
    ],filter=state.relationshipFilter||'all',rows=people.filter(p=>filter==='all'||p.kind===filter),chosen=rows.find(p=>p.id===state.selectedPerson)||rows[0];
    return `${head(ui,'人情与旧约','看支持的来因、受损的事实、未偿的承诺与对方自己的决定。',ui.go('family','回看两岸家人'),'人与人之间')}<div class="toolbar lp-filter">${[['all','所有相关人'],['family','家人'],['crew','同船伙伴'],['ally','独立盟友']].map(([v,l])=>set(ui,'relationshipFilter',v,l,`button ${filter===v?'active':''}`)).join('')}</div><div class="lp-person-layout"><nav class="lp-person-index" aria-label="相关人物">${rows.map(p=>set(ui,'selectedPerson',p.id,`<strong>${p.name}</strong><span>${p.relation}</span>`,`lp-person-option ${chosen.id===p.id?'selected':''}`)).join('')}<p>没有一条总好感值，能把这些具体的事相互抵销。</p></nav><article class="lp-person-dossier"><div class="lp-person-story">${scene(ui,chosen.scene,chosen.event)}<div><span>${chosen.relation}</span><h2>${chosen.name}</h2><p>${chosen.event}</p></div></div><div class="lp-person-claims"><section><h3>他／她现在要什么</h3><p>${chosen.wish}</p></section><section><h3>仍待兑现</h3><p>${chosen.owed}</p></section><section><h3>支持从哪里来</h3><p>${chosen.support}</p></section><section><h3>不能代答的边界</h3><p>${chosen.boundary}</p></section></div><div class="toolbar">${ui.go(chosen.target,chosen.label,'button primary')}${ui.go('chronicle','按年份回看旧事','button')}</div></article></div>`;
  }

  function factionList(state, ui) {
    const scope=state.factionScope||'all',rows=factions.filter(f=>scope==='all'||scope==='hirado'&&f.id==='hirado'||scope==='taiwan'&&f.id==='voc'||scope==='coast'&&['fujian','armed'].includes(f.id));
    const picked=rows.find(f=>f.id===state.selectedFaction)||rows[0]||factions[0],allied=scenarioIs(state,'临时结盟');
    return `${head(ui,'海上诸势力','旗号背后是具体的人、货源与船。按海域看门路，再问各家肯答应什么。',ui.go('sea-permits','查验令旗与凭据'),'海路与组织')}<div class="lp-sea-scope" role="group" aria-label="海域范围">${[['all','海路全览','所有已知往来'],['hirado','平户','合货与邻里商人'],['taiwan','大员周边','商馆与武装航次'],['coast','闽粤沿海','锚地、接应与通路']].map(([v,t,note])=>set(ui,'factionScope',v,`<strong>${t}</strong><span>${note}</span>`,`lp-scope-stop ${scope===v?'selected':''}`)).join('')}</div>${allied?`<section class="lp-alliance-compact">${stamp('拟定一航 · 只读盟约情境')}<h3>各自留船，只把这一航的接应说定</h3><div>${fact('我方投入','自有船与货位')}${fact('盟船投入','熟水手、火器与沿岸消息')}${fact('适用范围','同一航次、约定会合海段')}${fact('仍各自决定','掌船、分利、撤回与担损')}</div><p>临时合作不自动变为上下隶属。未写明求援信号与不得擅撤的接应，不把“结盟”当作永久保护。</p>${ui.go('diplomacy','把接应事项逐条写明','button primary')}</section>`:''}<div class="lp-factions-layout"><section class="lp-faction-network">${rows.map(f=>`<button type="button" class="lp-faction-row ${f.id===picked.id?'selected':''}" data-action="set" data-key="selectedFaction" data-value="${f.id}">${portrait(ui,f.portrait,'')}<span><strong>${f.name}</strong><small>${f.reach}</small><small>关切：${f.interest}</small></span><em>${f.short}</em><span>${f.status}</span></button>`).join('')}<div class="lp-faction-legend"><span>同港 ≠ 同一利益</span><span>同旗 ≠ 同一授权</span><span>同国籍 ≠ 同一阵营</span></div></section><aside class="lp-faction-aside"><span class="gold">当前所看 · ${picked.status}</span><h2>${picked.name}</h2><p>${picked.detail}</p>${fact('眼下关切',picked.interest)}${fact('可知范围',picked.reach)}${fact('尚待核实','具体船数、人手与这一航的条件')}${ui.go('faction-detail','展开往来档案','button primary')}${ui.go('diplomacy','把具体条件摆上桌','button')}</aside></div>`;
  }

  function factionDetail(state, ui) {
    const f=factions.find(x=>x.id===state.selectedFaction)||factions[0],unknown=scenarioIs(state,'情报不足'),tense=scenarioIs(state,'关系紧张');
    const offers={hirado:['合货与货位','资金、封货与按约结算','各家自己决定是否合货'],fujian:['同航接应','熟水手、独立船与沿岸消息','各船保留自己的掌船人'],voc:['委托与来路','货源、翻话与特定航次条件','商馆与船长未必同一意见'],armed:['眼前放行','收费艇、压货与某段通路','临时停手不等于永久和解']}[f.id];
    return `${head(ui,f.name,`${f.reach} · 往来条件与已知范围`,ui.go('factions','返回诸势力'),'一份组织档案')}<div class="lp-faction-detail"><aside class="lp-faction-figure">${portrait(ui,f.portrait,`${f.name}的代表形象`,'lp-faction-full')}<div class="lp-faction-figure-caption">人物为界面代表形象；不是某位史实人物的肖像原件。</div>${stamp(unknown?'尚缺核实信息':f.status)}</aside><section><div class="tag-list">${ui.pill(f.short)}${ui.pill(f.reach)}</div><h2>${offers[0]}</h2><p class="lp-lead">${f.detail}</p><div class="lp-faction-facts"><section><h3>他们掌握什么</h3><p>${unknown?'船数、人手与本航授权尚缺可核信息；不以空白推成零实力。':offers[1]}</p></section><section><h3>不能替谁答应</h3><p>${offers[2]}</p></section><section><h3>我方应先备什么</h3><p>货物来路、可投入资源、退出与担损办法。只谈具体的一航，不许无条件远期保证。</p></section></div>${tense?`<section class="lp-contact-restriction"><h3>眼前会面只核争议，不许新承诺</h3>${fact('暂缓事项','追加出资、借旗通行与未定接应')}${fact('仍可交代','原货来路、既欠与在场见证')}<p>先把未说清的责任摆上桌，对方没有答应恢复旧有信任。此处不凭一个称谓扣总好感或替所有商人表态。</p><button class="button" disabled>旧议未明，暂不追加合作</button></section>`:''}<h3>往来事项</h3><ul class="lp-records"><li><span>已知</span><div><strong>${f.interest}</strong><p>这是能够据当前剧情与关系明确的关切，不等于所有条件已经答应。</p></div></li><li><span>未定</span><div><strong>${scenarioIs(state,'谈判中')?'已有拟议事项，尚待对方答复':'尚未写定下一航的条件'}</strong><p>分利、接应、交割与通路适用范围须另立条目。</p></div></li></ul><div class="toolbar">${ui.go(unknown?'intelligence':'diplomacy',unknown?'先补能核实的消息':tense?'仅就旧议澄清责任':'准备具体交涉','button primary')}${ui.go('sea-permits','查现有凭据的边界','button')}</div></section></div>`;
  }

  function diplomacy(state, ui) {
    const offer=state.diplomacyOffer||'cargo',f=factions.find(x=>x.id===state.selectedFaction)||factions[0],share=Math.max(20,Math.min(50,Number(state.diplomacyShare||35)));
    const choices={cargo:{title:'合货 · 各自出资，各记来路',left:['我方提供','自有货与本航可支用银','本次可支用 '+n(state.silver)+' 两'],right:['对方须确认','验货、认出资与分利办法','是否合货由对方决定'],terms:['自有货与托运封货分别记。','按实际投入议分利，不能保证每航必得。','货损、耽期、退伙与交验办法先说明。'],cost:'只登记拟议条件，尚未扣银或装货。'},escort:{title:'同航 · 接应范围先写定',left:['我方提供','可协商的接应船与人手','在船 '+state.crew+' 人，不自动挪用'],right:['对方须确认','各船发令与撤回的边界','不交出自己的掌船权'],terms:['各船保留自己的掌船人。','预先说定求援信号与不得擅撤的接应。','改变安排前通知同航船，不用事后收益代替说明。'],cost:'此页不自动派走船员；接受正式约定仍需实际人船条件。'},cease:{title:'停手 · 只谈眼前这段水路',left:['我方提出','停止眼前相互逼近，核对人货','保留退路，不先许永久服从'],right:['对方须确认','这一段通行与放人条件','不能替别处武装作保'],terms:['本次暂缓追逐不抹去旧账。','人、货与旧有争议分别核对。','只适用眼前海段，离开后不称永久保护。'],cost:'停手未获答应前，不能把当前海面标作安全。'}},c=choices[offer]||choices.cargo;
    const proposalKey=`diplomacy-proposal-${f.id}-${offer}`,submitted=state[proposalKey]==='submitted',refused=scenarioIs(state,'对方拒绝'),unmet=scenarioIs(state,'条件未落实'),identity=scenarioIs(state,'身份改变'),authorityReady=Boolean(state.diplomacyAuthorityConfirmed);
    return `${head(ui,'一件一件谈清楚',`${f.name} · ${f.reach}`,ui.go('faction-detail','回到往来档案'),'交涉与责任')}<div class="lp-diplomacy-context">${stamp(refused?'此提议被拒绝':submitted?'已留拟议草案':'尚待写定')}<span>不因登记提议自动结盟、通行或发报酬。</span></div><div class="lp-negotiation"><aside><h3>这次只谈一件</h3>${[['cargo','合货出资'],['escort','盟船接应'],['cease','眼前停手']].map(([v,l])=>set(ui,'diplomacyOffer',v,l,`lp-negotiation-option ${offer===v?'selected':''}`)).join('')}<p>${f.detail}</p>${ui.go('relationships','先回看人的旧事','text-button')}</aside><article class="paper lp-negotiation-paper"><div class="lp-negotiation-parties"><div><span>${c.left[0]}</span><strong>${identity?'受抚后的一官船队 · 本次差遣待核':c.left[1]}</strong><small>${identity?'1628年受抚后 · 游击职分，不扩大为后来官衔':c.left[2]}</small></div><div><span>${c.right[0]}</span><strong>${c.right[1]}</strong><small>${c.right[2]}</small></div></div><h2>${c.title}</h2>${unmet?`<section class="lp-proposal-prerequisites"><h3>这份提议还不能交出去</h3><dl><dt>货物来路</dt><dd>有货名，尚缺双方可对照的封货清单</dd><dt>接应人船</dt><dd>尚未约定求援信号与不得擅撤的范围</dd><dt>交割与退出</dt><dd>短损责任、退出后担损尚未写定</dd></dl><p>先到货栈核交验，再与同航者逐条议定。登记草案不会替这些前提作保证。</p>${ui.go('contract-detail','核对封货与交验','button')}${ui.go('relationships','问明各方的投入与边界','button')}</section>`:identity?`<section class="lp-authority-change"><h3>身份变了，授权范围也要重新核</h3><ol><li>私下合货与公事差遣分开，不拿旗号替私债背书。</li><li>只说明本次可发令的人船，不把原盟友自动纳为下属。</li><li>旧约、旧欠与对方是否愿意合作仍须另谈。</li></ol>${ui.action('toggle',authorityReady?'☑ 已核本次身份与发令边界':'□ 核对：本次身份与发令边界','lp-check-button',{key:'diplomacyAuthorityConfirmed'})}<p>确认仅记录阅读核对，不发新凭据、不改实际阵营。</p></section>`:''}<ol class="lp-terms">${c.terms.map(t=>`<li>${t}</li>`).join('')}</ol>${offer==='cargo'?`<div class="lp-proposal-share"><span>拟议船员份额 · 尚非已成立条款</span><div class="toolbar">${[25,35,45].map(v=>set(ui,'diplomacyShare',v,`${v}%`,`button ${share===v?'active':''}`)).join('')}</div></div>`:''}<div class="lp-negotiation-cost"><strong>登记后会发生什么</strong><p>${c.cost}</p></div>${refused?fieldNote('对方拒绝当前事项','可以换谈另一件事，或结束会谈；不会凭空扣掉人物好感或替对方改主意。','warning'):''}${action(ui,'set',submitted?'这份草案已登记':'登记这组拟议条件','button primary',{key:proposalKey,value:'submitted'},refused||submitted||unmet||identity&&!authorityReady)}${submitted?`<div class="lp-paper-feedback"><strong>草案留在本事项中</strong><p>${f.name} · ${offer==='cargo'?`合货 / 拟议船员份额${share}%`:offer==='escort'?'同航接应 / 各船独立':'临时停手 / 限当前海段'}。对方尚未承诺，未产生自动资源变化。</p></div>`:''}<div class="toolbar">${ui.go('factions','结束本次会谈','text-button')}${ui.go('sea-permits','再查通行与授权范围','text-button')}</div></article></div>`;
  }

  function seaPermits(state, ui) {
    const docs={cargo:{title:'合货与船货清单',kind:'双方留照',issuer:'合货商与船主',range:'本航装卸、封货与交割核验',holder:'清单上写明的承接者',valid:'仅证明受谁所托、带了什么',limit:'不包含官身、武装通行或他方保护承诺',note:'换港、换船与转手之后，重新核对船数、箱印与交接者。'},tally:{title:'过水木筹',kind:'一段旧关系',issuer:'收费武装一方',range:'对方自行认定的一段水路',holder:'被核对的船与来人',valid:'对方是否仍承认须当面问',limit:'熟悉旗色与木筹不能约束另一支船队',note:'权力来自船与武器，不因为一块木筹就成了普遍准行。'},commission:{title:'荷方委托证明',kind:'特定航次',issuer:'相关荷方委托者',range:'所写的雇佣、翻话与航次关系',holder:'文书写明的经手人',valid:'须结合委托内容与眼前对象',limit:'在另一方巡船面前可能引来扣问',note:'吕宋方向遭遇、毁纸与脱离属于本剧具体冒险，不伪造西属港务法令。'},flag:{title:'保护旗与官身文书',kind:'随生涯变化',issuer:'须按当时的官身与授权核对',range:'不得脱离颁发者与时代条件',holder:'不因挂同色旗就自动同一授权',valid:'受抚之后另有报效责任',limit:'同旗商船与截船者仍可能发生纠纷',note:'1628受抚、授游击是骨架；这里不把后期头衔倒置给早年。'}},id=state.selectedPermit||'cargo',d=docs[id]||docs.cargo,open=Boolean(state.permitOpen),destroyed=scenarioIs(state,'凭据已毁');
    return `${head(ui,'令旗与通行凭据','木筹、委托、合货约与官旗分别核对。持有一份，不等于处处通行。',ui.go('route-plan','对照本航路'),'谁颁，管到哪里')}<div class="lp-document-tabs">${Object.entries(docs).map(([key,x])=>set(ui,'selectedPermit',key,`<strong>${x.title}</strong><span>${x.kind}</span>`,`lp-document-tab ${id===key?'selected':''}`)).join('')}</div><div class="lp-permits"><article class="paper lp-pass ${destroyed?'lp-document-invalid':''}"><div class="lp-pass-top"><span>${d.kind}</span><span class="lp-seal">${destroyed?'失效':'查验'}</span></div><h2>${d.title}</h2><p>${d.note}</p><dl><dt>出具一方</dt><dd>${d.issuer}</dd><dt>适用水域</dt><dd>${d.range}</dd><dt>适用对象</dt><dd>${d.holder}</dd><dt>有效条件</dt><dd>${destroyed?'此毁纸情境中原件已毁，不能重新使用。':d.valid}</dd><dt>已知漏洞</dt><dd>${d.limit}</dd></dl>${ui.action('toggle',open?'收起查验事项':'展开查验事项','button',{key:'permitOpen'})}${open?`<div class="lp-pass-detail"><strong>逐项比对，不只看印色</strong><ul><li>船、人、货与文书写的是不是同一方。</li><li>眼前拦船者是否承认这份关系。</li><li>换船、转货、时代与职分是否已经改变。</li></ul></div>`:''}</article><aside class="lp-permit-register"><h3>这份凭据不能替你做什么</h3><div><strong>不能证明全部货物归你</strong><p>货箱上的封记与原主线索仍须另辨。</p></div><div><strong>不能替别处武装答应</strong><p>一方认的证明，另一方可能不认，甚至因它扣问。</p></div><div><strong>不能免去官身义务</strong><p>官旗扩大通路，也改变报效责任与旧盟关系。</p></div>${ui.go('intelligence','查眼前对象的消息','button')}${ui.go('chronicle','按年份核对身份','text-button')}<p class="small muted">此处为凭据档案与适用边界；浏览不等于凭空获得原件。</p></aside></div>`;
  }

  function bountyBoard(state, ui) {
    const kind=state.bountyKind||'private',accepted=acceptedContractIds(state).includes('salvage'),doubtful=scenarioIs(state,'来源存疑'),risk=scenarioIs(state,'本人被追索'),consequences=scenarioIs(state,'后果已发生');
    return `${head(ui,'追索与酬报','发布者、所求、根据与牵连先核对。私人的价码，不装成官府公文。',ui.go('intelligence','核消息来路'),'是谁出的银')}<div class="toolbar lp-filter">${[['private','民间托付'],['official','官府文告'],['risk','与我相关的风险']].map(([v,l])=>set(ui,'bountyKind',v,l,`button ${kind===v?'active':''}`)).join('')}</div>${kind==='official'?empty(ui,'当前没有可核的官府悬赏文告','所见民间追索不冒充官方授权。不能为了填一块榜，造一份带官印的公文。','sea-permits','对照文书授权范围'):kind==='risk'||risk||consequences?`<section class="lp-private-pursuit"><div><span>${stamp('民间追索 · 剧中情境','warning')}</span><h2>${consequences?'人已被换回，舍掉的货与旧恩留在这里':'别人给你开的另一张价码'}</h2><p>被截集团私雇追索者，新伙计的出卖与杜七舍货换人沿本剧具体情节书写，不是官府通缉令。</p></div><dl><dt>先查</dt><dd>钱从谁手里来、追的是人还是货</dd><dt>牵连</dt><dd>接触过的买主、同船人与盟船</dd><dt>不能据此认定</dt><dd>所有海商同一立场，或任一国籍的人必为敌人</dd></dl>${consequences?`<ol class="lp-consequence-record"><li><strong>追索已经牵连同船人</strong><span>私人追索与新伙计出卖沿 a3_s8 剧中正线留档。</span></li><li><strong>杜七舍货换人</strong><span>一官获救；盟友自己的损失没有自动获偿。</span></li><li><strong>后续仍需承担</strong><span>偿还、接应与对方自己的决定分别记，不能领一笔酬银抹平。</span></li></ol>${ui.go('relationships','回看未偿的旧恩','button primary')}`:''}<div class="toolbar">${ui.action('toggle',state.bountyRiskNoted?'风险已记下':'将此风险留入本次记录','button primary',{key:'bountyRiskNoted'})}${ui.go('relationships','看谁付过真实代价','button')}</div></section>`:`<div class="lp-bounty-layout"><article class="paper lp-bounty-notice"><span class="lp-bounty-kind">民间寻货酬报</span><h2>寻回漂失米粮</h2><p>报信与带回货物分别议酬。凭箱印、封条与在场见证交验，不凭一句转述认定原主。</p><div class="lp-bounty-reward"><span>验明后酬</span><strong>160 <small>两</small></strong></div><dl><dt>托付人</dt><dd>受损船主，交验时本人或明示经手者在场</dd><dt>寻访处</dt><dd>近岸漂流带，不先许确切找回日</dd><dt>须辨认</dt><dd>箱印、封条、货数与原主说明</dd><dt>先后</dt><dd>先救人，争议货另封存</dd></dl>${doubtful?fieldNote('来源尚待核实','此情境停用承接，先核对发布者与原主根据。','warning'):''}${action(ui,'accept-contract',accepted?'寻货委托已记入日志':'登记承接寻货','button primary',{item:'salvage'},accepted||doubtful)}<p class="small">承接不会立即领取160两；找到并交验之后仍待对方验明。</p></article><aside><section class="lp-bounty-caution"><h3>核对发布者</h3><p>谁能说明货物来路、谁有权认领，不能只听酬报数额。</p>${ui.action('toggle',state.bountySourceOpen?'收起发布者核对项':'展开发布者核对项','button',{key:'bountySourceOpen'})}${state.bountySourceOpen?'<ul class="lp-publisher-checks"><li>请对方当面说明货印与短少。</li><li>核与原货单或在场人是否一致。</li><li>有冲突先封存，不能先售后辨。</li></ul>':''}</section><section><h3>还有另一张价码</h3><p>私人报复与索货可能牵连接触者。它不等于官府授权，也不代替货物归属核实。</p>${set(ui,'bountyKind','risk','展开与我相关的风险','button')}</section>${ui.go('contract-board','回委托板分清责任','text-button')}</aside></div>`}`;
  }

  function home(state, ui) {
    const stage=state.previewScenario||'初立屋檐',stages={'初立屋檐':['zheng_a2_s2','两个人的屋檐','约1622／1623—1624前 · 平户','一起选下的屋，并没有让生活忽然宽裕。灯下还有要商量的事。'],'隔海两地':['zheng_a2_s5','信跨过海，人仍在两岸','1624之后 · 平户与船上','母亲画来一张船，也问下一次托话经过谁。家用与归期仍要分别说明。'],'短暂重聚':['zheng_a6_s2','门外叫成功，家中仍叫福松','1645 · 福建','一桌饭是真实的轻快；每个人在门外所认定的路，已经有所不同。'],'分途之前':['zheng_a6_s3','箱子重新放下','1646 · 福建','指令没有替家人给出同一个答复。亲情仍在，每个人的去向却不再由一人安排。']},s=stages[stage]||stages['初立屋檐'];
    const sent=sentRecords(state),remit=sent.reduce((a,x)=>a+Number(x.amount||0),0);
    return `<section class="lp-home"><div class="lp-home-scene">${scene(ui,s[0],s[1])}<div class="lp-home-copy"><span>${s[2]}</span><h2>${s[1]}</h2><p>${s[3]}</p></div></div><nav class="lp-home-doors" aria-label="家中事务">${[['family','两岸家人','各自的近况、愿望与责任'],['letters','收在袋里的信',`${sent.length}封本次寄件 · 两封剧中来信`],['child-growth','孩子的来路','福松、森与成功的不同称呼'],['send-letter-remittance','写信与家用','把去向、计划与银额分别说明']].map(([id,t,d])=>`<button type="button" data-go="${id}"><strong>${t}</strong><span>${d}</span>${ui.icon('arrow')}</button>`).join('')}</nav><div class="lp-household-business"><section><span>还没有说完的话</span><h3>下次归期若还未定，也先写明</h3><p>告诉家中你已经应下什么，而不是等新航有利以后再补一个解释。</p>${ui.go('send-letter-remittance','在灯下写明安排','button primary')}</section><section><span>家用另有一笔</span><h3>${remit?`${n(remit)}两已托船，仍等回音`:'未见本次实际汇银记录'}</h3><p>写好、托寄、收到不是同一件事。家用与合货周转不悄悄相混。</p>${ui.go('accounts','查家用与周转账','button')}</section><aside><h3>信路留痕</h3><ol><li>写明收信人与安排</li><li>交给问明来路的托话人</li><li>随船在途，等下一次回音</li></ol>${ui.go('letters','查看收寄状态','text-button')}</aside></div></section>`;
  }

  function family(state, ui) {
    const years={'约1622／1623':{image:'zheng_a2_s2',place:'平户',title:'选择同一个屋檐',people:[['田川氏','留在平户，一起安顿日常','亲属原有更省心的安排，她也为这一处退了一步。','生活上的窘迫，需要两个人商量。'],['一官','仍是随船做事的人','放下一趟能添分成的差事，和她住进小屋。','远行与挣钱，不能自动代答在家的安排。']],note:'相识、住屋与灯夜场面为文学演绎，早年编年保留约数。'},'1624':{image:'zheng_a2_s4',place:'平户 / 大员船上',title:'孩子的日子先在岸上',people:[['田川氏','平户，亲属来帮','照顾福松，也想先知道一官下一程去哪里。','归期与家用分别写明，不由旁人先转述。'],['一官','大员附近的船上','有回船可同行，却先答应了下一航。','认下自己作出的安排，再写回信。'],['福松','幼年，母亲照护','出生的喜讯随信到了海上。','婴儿不参与航海指挥，也不会替母亲画船。']],note:'1624福松生于平户为历史节点；家信、返家机会与具体取舍来自本剧。'},'1630':{image:'zheng_a5_s1',place:'平户 → 福建',title:'一程送长子，不是一家同行',people:[['田川氏','平户，与幼子继续生活','同意长子赴明，也亲手承受分隔。','没有替自己写定同一趟归期。'],['福松','由亲属照护渡海','去见父亲，开始读书与新的生活。','带着自己选的玩物，不是独自操船过海。'],['郑芝龙','福建，接回长子','能安排读书、家中教养与受保护的位置。','不能跳过父子重新认识的陌生。']],note:'1630赴明、亲属照护与母亲未同行有资料依据；行李、小碗与对白为创作。'},'1645':{image:'zheng_a6_s2',place:'福建',title:'母亲叫福松，门外称成功',people:[['田川氏','渡海后团聚','仍用小时候的称呼认回儿子。','她的家中位置，不等于替政治立场裁判。'],['郑芝龙','家中与军务之间','为儿子的前程骄傲，也渐见自己的安排不再包办一切。','荣耀背后的人和路，须重新认识。'],['郑成功','获赐姓朱，名成功','家中的福松与门外的职分并存。','已经有自己认定的责任。']],note:'1645团聚与赐姓改名是骨架；饭桌、系带与私下话为文学演绎。'},'1646':{image:'zheng_a6_s4',place:'福建 / 北行途中',title:'每个人各答自己的去向',people:[['田川氏','留在福建','取回行李，不随那一程同行。','私人决定沿剧中场面书写；罹难不作操作惩罚。'],['郑芝龙','降清后被挟北上','未能自由返航。','令旗没有替家人给出同一个答复。'],['郑成功','留在福建海上','不从父亲，继续自己的路。','不安排一场和平舰队传位来抹平分途。']],note:'降清、被挟北上、成功不从与田川氏罹难保留固定骨架；不拍定有争议的死亡方式。'}};
    const year=state.familyYear||'1624',f=years[year]||years['1624'];
    return `${head(ui,'家人与彼此的路','同在一家，仍各有愿望、责任与不能代答的决定。',ui.go('home','回到屋檐下'),'海的两岸')}<div class="toolbar lp-family-years">${Object.keys(years).map(y=>set(ui,'familyYear',y,`${y}年`,`button ${year===y?'active':''}`)).join('')}</div><div class="lp-family-header"><div>${scene(ui,f.image,f.title)}</div><section><span>${f.place}</span><h2>${f.title}</h2><p>船路和信路可以把人相连，不能让一家自动认定同一条去路。</p><div class="toolbar">${ui.go('letters','读两岸来往','button primary')}${ui.go('child-growth','看孩子怎样长成自己','button')}</div></section></div><div class="lp-family-persons">${f.people.map(([name,where,wish,boundary])=>`<article><div><h3>${name}</h3><span>${where}</span></div><section><strong>眼下的生活与愿望</strong><p>${wish}</p></section><section><strong>责任与不能代答的事</strong><p>${boundary}</p></section></article>`).join('')}</div><div class="lp-family-boundary"><strong>把年份与私事分清</strong><p>${f.note}</p>${ui.go('history-notes','史实与创作说明','text-button')}</div>`;
  }

  function childGrowth(state, ui) {
    const entries={'1624':['幼年 · 平户','福松','母亲与亲属照护','孩子的日子先在岸上。母亲画来一张船，旁边留空，等孩子长大自己添。','父亲从信中知道孩子的变化，亲情不能用远航获利替代。','zheng_a2_s5'],'1630':['渡海 · 福建','福松，后名森','亲属照护赴明，父亲安排读书','得到一条更广的读书路，也要重新认识父亲。母亲没有在同一程同行。','父亲给了受保护的位置，孩子也会认真相信那位置背后的朝廷。','zheng_a5_s2'],'1634':['剧中短航 · 福建外海','森','舱口受照应，不在斧与水边','风浪里舍去主桅保全人船，是本剧的父子生活铺垫，不是已核的郑氏携子风暴记录。','看见能力，也看见父亲必须舍掉珍惜的东西。','zheng_a5_s7'],'求学':['1630之后—1645以前','森','读书、求学，渐有自己的交结','成长不能用点数购买立场。读过的书与认识的人，使他逐渐认定自己的方向。','教养与前程形成自主判断，不是父亲永远能收回的安排。','zheng_a6_s1'],'1645':['1645 · 福建','成功','获赐姓朱，领受新的职分','家中母亲仍叫福松，门外已经有人称国姓爷。荣耀与责任走入同一个屋檐。','他有了自己认定的朝廷与应办的事。','zheng_a6_s2'],'1646':['1646 · 福建','郑成功','不从父亲降清，走自己的路','父亲不能用过去的供养与教养买下儿子今日的立场。此处不开放付费改变既定分途。','亲情仍在，决定不再由一人代答。','zheng_a6_s4']};
    const year=state.childYear||'1630',e=entries[year]||entries['1630'];
    return `${head(ui,'福松、森与成功','名字、所处与责任随年份改变。成长是经历，不是一栏可购买的属性点。',ui.go('family','回到两岸家人'),'一个孩子长成自己')}<div class="lp-growth-layout"><nav class="lp-growth-years" aria-label="成长节点">${Object.entries(entries).map(([y,x])=>set(ui,'childYear',y,`<strong>${y}</strong><span>${x[1]} · ${x[0]}</span>`,`lp-growth-year ${year===y?'selected':''}`)).join('')}</nav><article class="lp-growth-story">${scene(ui,e[5],e[0])}<div><span class="gold">${e[0]}</span><h2>${e[1]}</h2><div class="lp-growth-role"><span>这一阶段的照护与责任</span><strong>${e[2]}</strong></div><p>${e[3]}</p><div class="lp-growth-relationship"><h3>父子之间留下了什么</h3><p>${e[4]}</p></div><div class="toolbar">${ui.go('letters','看那时往来的话','button primary')}${ui.go('chronicle','与编年边界对照','button')}</div></div></article></div>`;
  }

  function letters(state, ui) {
    const folder=state.letterFilter||'received',person=state.letterPerson||'all',sent=sentRecords(state),draft=String(state.letterDraft||'').trim();
    const rows=visibleLetters(state).filter(x=>person==='all'||person==='self'&&(x.personal||x.id==='reply')||person==='tagawa'&&!x.personal&&x.id!=='reply');
    const picked=rows.find(x=>x.id===String(state.selectedLetter))||rows[0];
    const folders=[['received','已收到',2],['sent','已托寄',sent.length+1],['draft','已写未托',draft?1:0],['unknown','仍待回音',sent.length+1]];
    return `${head(ui,'家书匣','字写好、托上船、走过海、见到回音，各有一个明确的位置。',ui.go('send-letter-remittance','另写一封家信','button primary'),'收好这些私人话语')}<div class="lp-letterbox"><aside><span class="lp-thread-loop"></span><h3>红线袋</h3>${folders.map(([v,l,c])=>set(ui,'letterFilter',v,`${l}<span>${c}</span>`,`lp-letter-folder ${folder===v?'selected':''}`)).join('')}<div class="lp-mailbox-route"><strong>信路</strong><span>船上落笔</span><span>交给托话人</span><span>随船在途</span><span>等收到的回音</span></div>${ui.go('home','收好信，回到家中','text-button')}</aside><section><div class="lp-mailbox-top"><h3>${folders.find(x=>x[0]===folder)?.[1]||'往来家书'}</h3><div class="toolbar">${[['all','所有写信人'],['tagawa','田川氏'],['self','一官']].map(([v,l])=>set(ui,'letterPerson',v,l,`button subtle ${person===v?'active':''}`)).join('')}</div></div>${folder==='draft'?(draft?`<article class="paper lp-draft-letter"><div><span>尚未交托 · 不作寄件回执</span><strong>给 ${ui.e(state.letterRecipient||'田川氏')}</strong></div><h2>留在灯下的草稿</h2><p>${ui.e(draft)}</p><div class="lp-draft-footer"><span>${draft.length}字 · 拟附银${n(state.remittanceDraft||0)}两，尚未支付</span>${ui.go('send-letter-remittance','继续写这封信','button primary')}</div></article>`:empty(ui,'这里没有未托寄的草稿','写下几句安排后，草稿会留在当前会话；空正文不会被当成寄件。','send-letter-remittance','坐下来写信')):rows.length?rows.map(x=>`<article class="lp-envelope ${picked.id===x.id?'lp-envelope-selected':''}"><div><span>${ui.e(x.from)}</span><span>${ui.e(x.date)}</span></div><h2>${ui.e(x.title)}</h2><p>${ui.e(x.excerpt)}</p><div class="lp-envelope-attachments">${x.id==='boat'?`${stamp('附船图的剧情线索')}${stamp('一段学唱的调子')}`:x.personal?stamp(`附银 ${n(x.amount)} 两`):stamp(x.id==='reply'?'剧中留存的回信':'剧中留存的来信')}</div><div><span class="lp-letter-state">${folder==='unknown'&&x.state!=='已收到'?'尚无收到的回音':ui.e(x.state)}</span>${picked.id===x.id?ui.go('letter-detail','展开这封信','button'):set(ui,'selectedLetter',x.id,'取出这封信','button')}</div></article>`).join(''):empty(ui,'这格信袋里没有相符的信','可以换一个写信人。没有真实寄件时，不编出一封已托寄的新信。','send-letter-remittance','去写一封信')}<div class="lp-mailbox-footnote"><strong>未知送达，仍记未知</strong><p>已托寄的实际正文与附银可回读；收到与否，仍等一条回船的消息。</p></div></section></div>`;
  }

  function letterDetail(state, ui) {
    const available = visibleLetters(state);
    const selected = available.find(letter => letter.id === String(state.selectedLetter)) || available[0];
    const content = {
      birth: ['一官：', '母子平安。孩子哭得响，布够用，亲属也来帮过。福松两个字，已经叫了许多回。', '你先前只说到了埠，还没有答后面究竟要去哪里。若要再走，别让旁人先告诉我。', '家中有家中的日子。归期若还不能定，就把不能定的话写来。'],
      boat: ['一官：', '画了一张船给孩子看，船身画得宽，旁边留了空处，等他自己会画再添。', '调子也托来了，另写了怎么发音。你若唱不准，就请人再念一遍。', '上回没有说完的话，并没有就此算了。下次托话，是经过谁？'],
      reply: ['家中：', '下一航已经答应了。回平户的船还在，但我这一程先不同行。', '孩子的事，我读了几遍。银两另记一笔托回去，不能把它当作我已经回去。', '后面的归期仍须等新航程落定，我会再写明。']
    };
    const paragraphs = selected.personal ? String(selected.body || '').split(/\n\s*\n/) : content[selected.id];
    return `${head(ui, '灯下读信', `${selected.from} · ${selected.date}`, ui.go('letters', '收回信袋'))}
      <div class="lp-letter-reading"><aside>${scene(ui, selected.image, selected.title)}<span>${ui.e(selected.state)}</span>
        <p>${selected.personal ? selected.fixture?'只读寄件样例，用于查看完整正文与附银；本次没有扣款或交托。':'这封信已交给托话人，收到与否仍待回音。' : '这封信随船而来。私人的话，留在灯下慢慢读。'}</p>
        ${selected.personal ? `${fact('收信人', ui.e(selected.recipient))}${fact('随信家用', `${n(selected.amount)} 两`)}${fact('捎信费', '20 两')}` : ''}
      </aside><article class="paper lp-letter-paper"><div class="lp-letter-heading"><span>${selected.personal ? `寄给 ${ui.e(selected.recipient)}` : '家中往来'}</span><h2>${ui.e(selected.title)}</h2></div>
        ${paragraphs.map((paragraph, i) => `<p class="${selected.personal ? 'lp-sent-body' : i === 0 ? 'lp-salutation' : ''}">${ui.e(paragraph)}</p>`).join('')}
        <div class="lp-letter-signature">${selected.personal || selected.id === 'reply' ? '一官' : '平户 · 田川氏'}</div>
        <div class="lp-letter-afterword">${selected.personal ? `${selected.fixture?'只读样例':'已托寄'} · 随信家用 ${n(selected.amount)} 两 · ${ui.e(selected.date)}` : '随剧情留存的私人话语'}</div>
      </article></div>${scenarioIs(state,'回信待写')?`<section class="lp-reply-desk"><div><span>来信中的问题尚未答复</span><h3>先把这三件事写清</h3><ol><li>眼前已经答应哪一航，为什么没有随回船。</li><li>下一次托话经过谁，归期尚未定也照实写。</li><li>这回实际托多少家用，与捎信费分开记。</li></ol></div><aside><strong>${String(state.letterDraft||'').trim()?'已有未托的回信草稿':'回信草稿仍空白'}</strong><p>${String(state.letterDraft||'').trim()?ui.e(String(state.letterDraft).slice(0,120)):'先写几句自己的安排，再核托寄人和费用。'}</p>${ui.go('send-letter-remittance',String(state.letterDraft||'').trim()?'继续写这封草稿':'坐到灯下开始回信','button primary')}</aside></section>`:''}<div class="toolbar lp-reader-actions">${ui.go('send-letter-remittance', selected.personal ? '再写一封家信' : '写一封回信', 'button primary')}${ui.go('family', '看看海的两岸', 'button')}</div>`;
  }

  function sendLetter(state, ui) {
    const amount=state.remittanceDraft??Math.min(100,Math.max(0,state.silver-20)),body=state.letterDraft??'下一航已经应下。眼前有回平户的船，我却没有同行。我会把后面的安排写明，不让你从旁人处先听见。',recipient=state.letterRecipient||'田川氏',carrier=state.letterCarrier||'trusted',topic=state.letterTopic||'plan';
    const latest=sentRecords(state)[0]||state.lastLetter,sameDraft=Boolean(latest&&String(latest.body||'').trim()===String(body).trim()&&Number(latest.amount)===Number(amount)&&String(latest.recipient)===String(recipient));
    const total=Number(amount||0)+20,short=Math.max(0,total-state.silver),valid=String(body).trim().length>0&&Number.isInteger(Number(amount))&&Number(amount)>=0&&!short&&carrier==='trusted'&&!scenarioIs(state,'银两待筹')&&!sameDraft;
    const topics={plan:['已经答应哪一航','把已作出的安排说清，不让家中先听旁人的转述。'],return:['归期还不能定','若没有可守住的确日，就写明下一次何时再托话。'],money:['家用另有一笔','写清实际托寄多少，别把未来盈利当已经寄到。']};
    return `${head(ui,'把话托给一条船','写信、家用与托话人分别核对。交出去以后，还要等海路。',ui.go('letters','回到家书匣'),'灯下的安排')}<div class="lp-compose-layout"><section class="paper lp-compose"><div class="lp-compose-heading"><h2>写给家中</h2><span id="letter-character-count">${String(body).length} / 800字</span></div><div class="lp-reply-prompts"><span>先答哪件事</span><div class="toolbar">${Object.entries(topics).map(([v,x])=>set(ui,'letterTopic',v,x[0],`button ${topic===v?'active':''}`)).join('')}</div><p>${topics[topic]?.[1]||topics.plan[1]}</p></div><label class="field" for="letter-recipient">收信人<select id="letter-recipient"><option value="田川氏" ${recipient==='田川氏'?'selected':''}>田川氏 · 平户</option><option value="平户家中" ${recipient==='平户家中'?'selected':''}>平户家中 · 请亲属转交</option></select></label><label class="field" for="letter-body">信中要说的话<textarea id="letter-body" rows="8" maxlength="800" placeholder="归期若还未定，也照实写下。">${ui.e(body)}</textarea></label><p class="small">正文空白时不能托寄；当前草稿、收信人与拟附银会保留在本次会话。</p><label class="field" for="remittance">随信家用（两，可为零）<input id="remittance" type="number" min="0" max="${Math.max(0,state.silver-20)}" step="1" value="${ui.e(amount)}" inputmode="numeric"></label><p class="small">家用为零也可写信，捎信费20两仍须预留。</p></section><aside class="lp-mail-route"><h3>先核托话人，再封信</h3><div class="lp-carrier-options">${set(ui,'letterCarrier','trusted','<strong>陈添交给问明的回船</strong><span>已问船主，可捎小包与家信</span>',`lp-carrier-option ${carrier==='trusted'?'selected':''}`)}${set(ui,'letterCarrier','next','<strong>等待下一条可托的船</strong><span>尚未核实，不开放封信托寄</span>',`lp-carrier-option ${carrier==='next'?'selected':''}`)}</div>${route(['大员泊船处','可信托话人','平户亲属转交'])}<div class="lp-letter-bill">${fact('拟附家用',`${n(amount)} 两`)}${fact('捎信费用','20 两')}<div class="lp-fact"><span>本次合计</span><strong><output id="letter-total">${n(total)}</output> 两</strong></div><div class="lp-fact"><span>托寄后可支</span><strong><output id="letter-balance">${n(state.silver-total)}</output> 两</strong></div></div><div id="letter-submit-reason" aria-live="polite">${sameDraft?fieldNote('托寄凭据已入匣','这封信已经托寄，修改正文或家用后再寄新信。','warning'):!String(body).trim()?fieldNote('还没有要托出去的话','先写正文；空草稿不会扣银或生成寄件。','warning'):short||scenarioIs(state,'银两待筹')?fieldNote('银两仍待筹',short?`还差${n(short)}两，可减少拟附银，或先留下草稿。`:'本情境展示费用待筹。恢复正常状态后按实际预算核对。','warning'):carrier!=='trusted'?fieldNote('托寄人尚未落实','可以继续写草稿，确认有船与联系人以后再封信。','warning'):''}</div>${action(ui,'send-letter','核对后封信，交船托寄','button primary',{},!valid)}<p class="small muted">托寄不保证确日收到。下一航的收益也不会自动补记为家用已寄。</p>${latest?`<div class="lp-mail-receipt"><strong>最近一次已交托</strong><p>${ui.e(latest.title)} · 附银${n(latest.amount)}两。正文已留在寄件袋，可完整回读。</p>${ui.go('letters','看实际托寄记录','text-button')}</div>`:scenarioIs(state,'已经托寄')?fieldNote('尚无本次托寄回执','当前没有真实寄件，不能为状态预览虚构扣款或收到。'):''}</aside></div>`;
  }

  function voyageResult(state, ui) {
    const records=(state.transactions||[]).filter(t=>t.time==='刚刚'),incoming=records.filter(t=>t.delta>0).reduce((s,t)=>s+t.delta,0),outgoing=-records.filter(t=>t.delta<0).reduce((s,t)=>s+t.delta,0),pending=Object.values(state.contractDeliveries||{}).filter(v=>v==='pending').length;
    const cases={
      '顺利交割':{image:'zheng_a3_s1',title:'封货交清，银账与人船分别验明',stamp:'交割结清 · 界面样例',lead:'样例委托已完成双方交验。这里核对的是一份运输差事，不把它写成某次史实航次的账簿。',rows:[['代运生丝','原封12担 / 实交12担','无短少'],['完约报酬','280 两','已核收'],['本航支出','90 两','伙食与小修样例'],['本航净余','190 两','未加入真实现银']],next:'结清凭据留档，再安排家用与下一航',target:'accounts',label:'按实际账册另核本航'},
      '获利但失援':{image:'zheng_a3_s3',title:'自有货保住，顺生没有回来',stamp:'获利与责任并存 · 剧中正线',lead:'一官看见求援信号，却撤去说定的接应。顺生沉失、阿禾受伤，不能归咎传令人，也不被货物净余抵销。',rows:[['自有货','保住','收益另核'],['盟船顺生','沉失','接应责任未清'],['阿禾','受伤','照应与去留由人决定'],['原约接应','中途撤回','一官须说明']],next:'先见受影响的人，再把赔付与接应责任分开记',target:'relationships',label:'去见同船人与盟友'},
      '货损待偿':{image:'zheng_a3_s7',title:'到岸十担，另两担待辨担损',stamp:'交割有缺 · 界面样例',lead:'用代运十二担演示有损交验：十担可交，两担因封记和受潮待核。此份样例不会自动扣赔款或发报酬。',rows:[['原装封货','12 担','双方清单'],['可以交验','10 担','封记相符'],['短损待核','2 担','受潮 / 责任未定'],['完约报酬','280 两暂缓','不自动抵销赔付']],next:'补齐箱封、短损见证与双方说明，验明前保留争议',target:'contract-detail',label:'核对交验与短损事项'},
      '人船保全':{image:'zheng_a1_s3',title:'先把人带回，货物另留在海上',stamp:'撤回与救援 · 界面样例',lead:'本例选择先撤离险处并照应在船人员。货物损失仍另记，不为画面补造死亡名单，也不凭空发一笔救援酬报。',rows:[['在船人员',`${state.crew} 人待逐名点验`,'先接回人'],['船与帆索',`${state.hull}% / ${state.sails}%`,'按实际船况'],['放弃的货物','数量待核','不混作成交'],['可支用银',`${n(state.silver)} 两`,'实际资源未变']],next:'清点人船、安置需要照应的人，再辨货物归属与损失',target:'battle-damage',label:'先查看人船损伤'}
    },c=cases[state.previewScenario];
    if(c)return `${head(ui,'一航之后，逐项点验','人船、货物、银账与未清责任分别留下。',ui.go('accounts','展开实际账册'),'靠岸之后')}<div class="lp-voyage-top"><div class="lp-voyage-image">${scene(ui,c.image,c.title)}</div><div>${stamp(c.stamp)}<h2>${c.title}</h2><p>${c.lead}</p></div></div><section class="lp-settlement-sheet"><div class="lp-settlement-heading"><span>点验事项</span><span>数额 / 事实</span><span>结清范围</span></div>${c.rows.map(([a,b,d])=>`<div class="lp-settlement-row"><strong>${a}</strong><span>${b}</span><small>${d}</small></div>`).join('')}</section><div class="lp-voyage-aftercare"><div><h3>下一件应办的事</h3><p>${c.next}</p></div><div class="toolbar">${ui.go(c.target,c.label,'button primary')}${ui.go('quest-journal','把未结清的事留在册中','button')}</div></div><p class="lp-fixture-caption">本页情境不覆盖实际库存、现银、交验或伤亡记录；下方资源与账册仍以本次真实操作为准。</p><div class="lp-voyage-closing"><section><h3>本次实际人员与船况</h3>${fact('在船',`${state.crew} 人`)}${fact('船体 / 帆索',`${state.hull}% / ${state.sails}%`)}</section><section><h3>实际交验记录</h3>${fact('已提交待验',`${pending} 份`)}${ui.go('contract-board','展开实际委托','button')}</section><section><h3>实际动作银账</h3>${fact('收入 / 支出',`${n(incoming)} / ${n(outgoing)} 两`)}${fact('净变动',`${incoming-outgoing>0?'+':''}${n(incoming-outgoing)} 两`)}</section></div>`;
    return `${head(ui,'一航之后，逐项点验','先看人船，再辨货物，最后合银账。获利、受损与未兑现的约定并列留下。',ui.go('accounts','展开逐笔账册'),'靠岸之后')}<div class="lp-voyage-top"><div class="lp-voyage-image">${scene(ui,'zheng_a3_s1','两船会合的海上情境')}</div><div>${stamp('当前资源点验')}<h2>船与人回来，事情未必都结清</h2><p>下方数值来自本次实际操作；剧情画面用于说明航次语境，不据此补造一份历史战报。</p><div class="lp-voyage-statuses">${fact('在船人员',`${state.crew}人`)}${fact('船体 / 帆索',`${state.hull}% / ${state.sails}%`)}${fact('当前可支用',`${n(state.silver)}两`)}</div></div></div><div class="lp-voyage-closing"><section><h3>人船先点</h3><ul><li>核对在船与需要照应的人，不以盈利掩盖伤员。</li><li>船身${state.hull}%，帆索${state.sails}%，待修处另进船坞。</li><li>没有已记录伤亡名单，不凭空补出人数。</li></ul>${ui.go('crew-roster','清点在船人员','button')}${ui.go('ship-repair','逐处看待修','text-button')}</section><section><h3>货物再辨</h3>${fact('本船米粮',`${stock(state,'grain')}石`)}${fact('自有生丝',`${stock(state,'silk')}担`)}${fact('已提交委托',`${pending}份待对方验收`)}${ui.go('cargo-hold','自有、托运与封存分开点','button')}</section><section><h3>银账最后合</h3>${fact('本次动作收入',`${n(incoming)}两`)}${fact('本次动作支出',`${n(outgoing)}两`)}${fact('本次动作净变动',`${incoming-outgoing>0?'+':''}${n(incoming-outgoing)}两`)}<p class="small muted">不把往航留档再加进本次余额。</p>${ui.go('accounts','追每笔银的去向','button')}</section></div><div class="lp-voyage-aftercare"><div><h3>下一件应办的事</h3><p>家用收到没有、委托验收没有、接应责任与货损赔付有没有说清，都不会随靠岸自动完成。</p></div><div class="toolbar">${ui.go('quest-journal','打开尚未结清的册','button primary')}${ui.go('save-game','保存当前完整航程','button')}${ui.go('route-plan','再安排下一航','text-button')}</div></div>`;
  }

  function accounts(state, ui) {
    const tab=state.accountTab||'current',category=state.accountCategory||'all',records=Array.isArray(state.transactions)?state.transactions:[];
    const income=records.filter(x=>x.delta>0).reduce((s,x)=>s+Number(x.delta),0),spend=-records.filter(x=>x.delta<0).reduce((s,x)=>s+Number(x.delta),0),last=records.at(-1),opening=last?Number(last.balance)-Number(last.delta):Number(state.silver),matches=Math.abs(opening+income-spend-state.silver)<.001;
    const categories=[...new Set(records.map(x=>x.category||'其他'))],rows=records.filter(x=>category==='all'||(x.category||'其他')===category);
    const key=t=>`${t.title}|${t.balance}|${t.delta}`,chosen=records.find(t=>key(t)===state.selectedTransaction);
    const actualRemit=sentRecords(state).reduce((s,x)=>s+Number(x.amount||0),0);
    return `${head(ui,'船上账房','现银、用途、托付与尚欠逐项核对；未核实的责任不编成已经扣掉的银。',ui.go('voyage-result','回到人船点验'),'每笔各有来处')}<div class="lp-account-rebuilt"><section class="lp-cash-book"><span>现在可以支用</span><strong>${n(state.silver)} <small>两</small></strong><div class="lp-cash-reconciliation"><span>推算期初 ${n(opening)}</span><span>记入 ${n(income)}</span><span>付出 ${n(spend)}</span>${stamp(matches?'与现银相符':'余额待核',matches?'':'warning')}</div></section><aside class="lp-cash-purposes"><div><span>本次随信家用</span><strong>${n(actualRemit)} 两</strong><small>${actualRemit?'已托寄，仍等回音':'未见实际汇银记录'}</small></div><div><span>航次委托</span><strong>${acceptedContractIds(state).length} 份</strong><small>完约报酬尚待对方验收</small></div><div><span>争议与赔付</span><strong>金额待辨</strong><small>不凭空从现银中扣除</small></div></aside></div><div class="toolbar lp-account-tabs">${[['current','本次出入'],['archive','前航次留档'],['owed','用途与尚欠']].map(([v,l])=>set(ui,'accountTab',v,l,`button ${tab===v?'active':''}`)).join('')}</div>${tab==='current'?`<div class="toolbar lp-ledger-filter">${set(ui,'accountCategory','all',`全部 ${records.length}`,`button subtle ${category==='all'?'active':''}`)}${categories.map(c=>set(ui,'accountCategory',c,`${c} ${records.filter(x=>(x.category||'其他')===c).length}`,`button subtle ${category===c?'active':''}`)).join('')}</div><section class="lp-account-ledger"><div class="lp-ledger-heading lp-ledger-detailed"><span>时间 / 用途</span><span>这笔账</span><span>收支 · 两</span><span>该笔后余额</span><span>凭据</span></div>${rows.length?rows.map(t=>`<div class="lp-ledger-row lp-ledger-detailed ${chosen===t?'selected':''}"><div><strong>${ui.e(t.time||'本航')}</strong><small>${ui.e(t.category||'其他')}</small></div><div><strong>${ui.e(t.title)}</strong></div><strong class="${t.delta>0?'gold':''}">${t.delta>0?'+':''}${n(t.delta)}</strong><span>${n(t.balance)} 两</span>${set(ui,'selectedTransaction',key(t),'查这笔','button subtle')}</div>`).join(''):empty(ui,'此用途中还没有出入记录','按用途筛账只改变视图，不删除其他流水。',null,'')}<div class="lp-ledger-row lp-ledger-total"><strong>现存可支</strong><strong>${n(state.silver)} 两</strong><span>${matches?'逐笔与资源栏相符':'请先核对未匹配的记录'}</span></div></section>${chosen?`<section class="lp-ledger-document"><div><span>本船内部记账凭据</span><h3>${ui.e(chosen.title)}</h3><p>${ui.e(chosen.time)} · ${ui.e(chosen.category)} · ${chosen.delta>0?'收入':'支出'} ${n(Math.abs(chosen.delta))} 两</p></div>${fact('此笔后余额',`${n(chosen.balance)} 两`)}<p>此条由实际界面动作留下，不是官府公文，也不额外重复支付。</p></section>`:''}`:tab==='archive'?`<section class="paper lp-archive-ledger"><div class="lp-archive-title"><h3>前航次 · 已结留档</h3>${stamp('仅供回看，不再入现银')}</div><div class="lp-ledger-row"><strong>货物交售毛入</strong><strong>+3,200 两</strong><span>不等于净利</span></div><div class="lp-ledger-row"><strong>购货与周转</strong><strong>−1,540 两</strong><span>先扣货本</span></div><div class="lp-ledger-row"><strong>工钱、伙食与修补</strong><strong>−620 两</strong><span>同船人应得</span></div><div class="lp-ledger-row lp-ledger-total"><strong>该航净余</strong><strong>1,040 两</strong><span>往航已结，不重复领取</span></div><p>留档示例用于区分毛利与净余，不作为某次历史航次的财务原件。</p></section>`:`<div class="lp-owed-list"><article><div><span>家用 · 另列用途</span><h3>${actualRemit?'家用已经托船，仍需等收到的消息':'原定寄回的家用尚需安排'}</h3><p>${actualRemit?`本次实际托寄${n(actualRemit)}两，费用另在家书流水。`:'没有实际汇银记录时，不因寄了零两家信就标作家用已寄。'}</p></div>${ui.go('send-letter-remittance','安排信与家用','button')}</article><article><div><span>盟船与损失 · 尚待核实</span><h3>损船、伤人和接应，不只是一笔总数</h3><p>先辨实际发生了什么、谁须承担。未核金额保留待辨，不用其他用途的银悄悄填平。</p></div>${ui.go('relationships','查具体对象与旧约','button')}</article></div>`}`;
  }

  function tutorial(state, ui) {
    const topics={helm:{name:'操船与镜头',icon:'ship',target:'sailing-hud',steps:[['先看航向与船况','航向、航速和目标在航行HUD中分别显示。'],['在海图定下一程','先核目的地与避风处，不只看直线距离。'],['改变观察角度','镜头设置与航行辅助在设置页查看；网页原型不冒称已完成原生操船。'],['回到跟船与目标','需要时收起管理页，回到航行。']]},wind:{name:'风候与航路',icon:'compass',target:'weather-wind',steps:[['看当前风信','风向影响效率，不切断基本行动能力。'],['辨消息新旧','旧云势与旧风信不保证今日船期。'],['给退路留位置','核对避风处、补水点与同航船。'],['再问归期','没有确定抵达日，就把未定照实说。']]},chart:{name:'海图与补给',icon:'map',target:'route-plan',steps:[['先选目的港','看可用门路、停靠条件与消息日期。'],['比较停靠办法','沿岸与直航各有时间、费用和退路。'],['核粮水余舱','按人数与在航天数核建议量。'],['备妥再出发','确认船况、人员和委托接应。']]},trade:{name:'验货与成交',icon:'trade',target:'market',steps:[['区分货物归属','本船自有、托运与争议封货不混售。'],['看两种价','买价与卖价不同，不能将差价当固定利润。'],['填数量核限额','港市余货、银两与加权货位共同限额。'],['回账房复核','成交后库存、现银与流水应一起变化。']]},guns:{name:'炮击与装填',icon:'cannon',target:'battle-hud',steps:[['认本舷与射界','先看左、右舷与目标位置。'],['选弹种','实心弹、链弹与葡萄弹用途不同。'],['核弹药与装填','未装填完或本舷无弹时不下重复开炮指令。'],['复核损伤','命中与伤害须看战况，不凭按钮点击判断。']]},boarding:{name:'接舷与损管',icon:'people',target:'boarding',steps:[['先看是否值得靠近','火势、人数与船位会改变风险。'],['明确推进或守住','不同命令产生不同的船上安排。'],['给损管留人','补漏、压火与救伤不能被进攻全部占走。'],['必要时脱离','回到己船，先接回能接的人。']]},rescue:{name:'救援与接应',icon:'anchor',target:'battle-damage',steps:[['先把接应说定','各船知道信号、留守与回援边界。'],['不临时悄撤','改变安排会影响真实的人和船。'],['先救人再点货','落水者、伤员与火船船员先列入。'],['战后留责任','获利与失援同时记，不用净余遮住损失。']]},letters:{name:'家书与汇银',icon:'letter',target:'send-letter-remittance',steps:[['答复具体的事','去向、下一航与未定归期分别写明。'],['银与信分开算','家用可为零，捎信费仍要预留。'],['核托话人与回船','写好不等于已交托。'],['等收到的回音','寄件可回读，但不会自动标成家中已收。']]}}
    const topic=state.tutorialTopic||'helm',t=topics[topic]||topics.helm,index=Math.min(3,Math.max(0,Number(state.tutorialStep||0))),learned=Boolean(state[`tutorial-learned-${topic}`]||scenarioIs(state,'已学会')),optional=scenarioIs(state,'可跳过'),review=scenarioIs(state,'随时重看');
    return `${head(ui,'掌船手册','按眼前的事查一页；可以跳过，也能随时回来重看。',ui.go('port-hub','回到当前港口'),'短步骤与实处')}<div class="lp-manual-layout"><nav class="lp-manual-topics" aria-label="手册主题">${Object.entries(topics).map(([id,x])=>set(ui,'tutorialTopic',id,`${ui.icon(x.icon)}<span>${x.name}</span>${state[`tutorial-learned-${id}`]?'<small>已标记</small>':''}`,`lp-manual-topic ${topic===id?'selected':''}`)).join('')}</nav><article class="lp-manual-page"><header><span>${review?'回查 · ':''}${t.name}</span>${stamp(learned?'已标记学会':'可随时跳过')}</header>${optional?`<section class="lp-manual-decision"><h3>先去办眼前的事，也能再回来</h3><p>本段不会强制完成。跳过后保留各主题入口，不扣资源，也不替你标记已学会。</p>${ui.go('port-hub','跳过本段，回港口继续','button primary')}${set(ui,'tutorialStep',0,'留下来，从第一步看','button')}</section>`:learned?`<section class="lp-manual-mastery"><strong>本主题四项要点已看完</strong><p>标记是自己的阅读记录，不代表通过原生操船考核。需要时可以取消，再逐步查看。</p>${ui.action('toggle','取消本主题学会标记','button',{key:`tutorial-learned-${topic}`})}</section>`:review?`<section class="lp-manual-review"><h3>从待办直接查一页</h3><div class="toolbar">${set(ui,'tutorialTopic','chart','出港前核海图与补给','button')}${set(ui,'tutorialTopic','rescue','同航前核救援接应','button')}${set(ui,'tutorialTopic','letters','托寄前核家书与银两','button')}</div><p>可直接换主题、跳到相应步骤；不重置已留的阅读标记。</p></section>`:''}<div class="lp-manual-step-nav">${t.steps.map((s,i)=>set(ui,'tutorialStep',i,`${i+1}`,`button ${i===index?'active':''}`)).join('')}</div><h2>${t.steps[index][0]}</h2><p class="lp-lead">${t.steps[index][1]}</p><ol class="lp-manual-outline">${t.steps.map((s,i)=>`<li class="${i===index?'selected':''}"><strong>${s[0]}</strong><span>${s[1]}</span></li>`).join('')}</ol><div class="toolbar">${ui.go(t.target,'到对应界面试一项','button primary')}${index<3?set(ui,'tutorialStep',index+1,'看下一步','button'):ui.action('toggle',learned?'取消学会标记':'我已学会，留个标记','button',{key:`tutorial-learned-${topic}`})}</div><p class="small muted">操船、射击与镜头的正式效果仍以原生游戏验证为据；网页用于审阅界面与资源反馈。</p></article></div>`;
  }

  function defeat(state, ui) {
    const slots=(state.saves||[]).map((saved,index)=>({saved,index})).filter(x=>x.saved?.snapshot),recover=scenarioIs(state,'可恢复检查点'),failed=scenarioIs(state,'玩家操作失败'),fixed=scenarioIs(state,'剧情损失另记'),none=scenarioIs(state,'没有可用存档')||slots.length===0;
    return `<section class="lp-defeat"><div class="lp-defeat-image">${scene(ui,fixed?'zheng_a3_s3':'zheng_a1_s3',fixed?'失援的既定后果':'风浪与失货，先把人接回')}<div class="lp-defeat-image-label">${fixed?'责任留档，不以重试抹去':'先救人，再清点'}</div></div><div class="lp-defeat-copy"><span>${failed?'操作受挫 · 界面样例':recover?'恢复航程 · 先核快照':'这一路没有照原样走完'}</span><h2>${fixed?'有些结果，不能归成操作失误':failed?'这次没能守住撤离前的准备':'先把还能接回的人带回岸上'}</h2><p>${fixed?'既定剧中的失援、顺生沉失与家庭分途留在纪事与责任中，不用一次重试或付银把它们抹除。':failed?'样例原因：未完成进水处置便继续驶入风浪。以下仅演示失败说明与恢复入口，不宣称本次会话真的沉船或有人死亡。':'当前资源可继续检查。恢复只读取已经保存的完整快照，不把空槽标成可读。'}</p>${failed?`<ol class="lp-failure-chain"><li><strong>风险出现</strong><span>进水处尚未分派损管</span></li><li><strong>继续航行</strong><span>未在可用锚地处理船况</span></li><li><strong>应先重做</strong><span>停靠、分人处理、核对撤离路线</span></li></ol>`:''}<div class="lp-defeat-facts">${fact('当前船体',`${state.hull}%`)}${fact('在船人员',`${state.crew} 人`)}${fact('可支用银',`${n(state.silver)} 两`)}</div><section class="lp-recovery-ledger"><h3>${recover?'选择一份可恢复的完整快照':'可以恢复到哪里'}</h3>${!none?slots.map(({saved,index})=>`<div class="lp-recovery-slot"><div><strong>${ui.e(saved.name)}</strong><small>银${n(saved.silver)}两 · 船体${saved.hull}% · 完整资源快照</small></div>${ui.action('load','读取这段航程','button primary',{slot:index})}</div>`).join(''):recover?`<div class="lp-recovery-slot lp-fixture-slot"><div><span>只读存档样例 · 尚未写入本次会话</span><strong>出港前 · 核完粮水与接应</strong><small>船体72% · 船员38人 · 港口整备节点</small><p>实际槽中尚无快照。此卡展示恢复点的内容与边界，不能据此加载不存在的存档。</p></div><button class="button" disabled>样例不可读取</button></div>${ui.go('save-game','先保存一份实际完整快照','button primary')}`:`<div class="lp-recovery-empty"><strong>当前没有可用的本次会话存档</strong><p>保存一份航程后才会出现可读恢复点。空白槽不报读取成功。</p><button class="button" disabled>没有可读取的检查点</button></div>`}</section><div class="toolbar">${ui.go('battle-damage','检视人船损伤','button')}${ui.go('quest-journal','回看责任与后续','button')}${ui.go('main-menu','暂回主菜单','text-button')}</div></div></section>`;
  }

  function notificationLog(state, ui) {
    const filter=state.notificationFilter||'all',readFilter=state.notificationRead||'all',real=Array.isArray(state.notifications)?state.notifications:[],mode=state.previewScenario;
    const samples={
      '紧急待办':[{id:'sample-provisions',title:'长航前粮水缺口待核',body:'出港前先按38人、20日核粮。当前米粮80石，建议95石；还差15石，另核淡水与容器。',category:'整备',time:'出港前 · 样例',pageId:'supplies',read:false,urgent:true},{id:'sample-rescue',title:'接应信号尚未与同航船说定',body:'未确认撤回、求援与回援边界前，不能把护送准备标成完成。',category:'委托',time:'出港前 · 样例',pageId:'contract-detail',read:false,urgent:true}],
      '普通见闻':[{id:'sample-wind',title:'候潮水手说起两日后的风',body:'经验判断仍须临近出港再核，不据一句风信承诺到达日。',category:'见闻',time:'清晨 · 样例',pageId:'intelligence',read:false},{id:'sample-letter',title:'陈添问明一条回平户的船',body:'可以捎小包与家信。空位和船期仅限这一船，尚未替你托寄。',category:'见闻',time:'午后 · 样例',pageId:'letters',read:false}],
      '已读':[{id:'sample-read',title:'上一条风信已经看过',body:'已读只表示读过，出港前仍应重新核风。此条留档，不重复变成新提醒。',category:'见闻',time:'昨日 · 样例',pageId:'intelligence',read:true}],
      '相关事项已结束':[{id:'sample-closed',title:'买粮单已交清并留账',body:'示例买单：米粮1石、18两，交货与付款核对完成。记录只用于展示已结束消息，不增加库存或再次扣款。',category:'交易',time:'此前 · 样例',pageId:'accounts',read:true,closed:true}]
    };
    const demo=real.length===0&&samples[mode],records=demo||real,categories=[...new Set(records.map(x=>x.category||'见闻'))];
    const rows=records.filter(x=>(filter==='all'||x.category===filter)&&(readFilter==='all'||(readFilter==='read'?x.read:!x.read))),unread=records.filter(x=>!x.read).length;
    return `${head(ui,'船上消息','看过的留档，待办的指向原处。已读不代表事项已经办完。',ui.go('quest-journal','回到航海日志'),'让变更有去处')}<div class="lp-notification-summary"><strong>${unread}<small>条未读</small></strong><span>${records.length} 条${demo?'只读情境样例':'实际记录保留在本航'}</span><p>${demo?'本次尚无通知，以明确标记的样例展示消息层次；不会写入实际通知历史。':'交易、损伤、托寄与任务的变化不反复刷成相同提醒。'}</p></div><div class="lp-intel-controls"><div class="toolbar">${[['all','全部'],...categories.map(c=>[c,c])].map(([v,l])=>set(ui,'notificationFilter',v,l,`button ${filter===v?'active':''}`)).join('')}</div><div class="toolbar">${[['all','不限已读'],['unread','尚未读过'],['read','已读留档']].map(([v,l])=>set(ui,'notificationRead',v,l,`button subtle ${readFilter===v?'active':''}`)).join('')}</div></div><ol class="lp-notification-list">${rows.length?rows.map(x=>`<li class="${x.read?'lp-notification-read':'lp-notification-unread'} ${x.urgent?'lp-notification-urgent':''} ${x.closed?'lp-notification-closed':''}"><time>${ui.e(x.time||'本航')}<span>${ui.e(x.category||'见闻')}</span></time><div><div class="lp-notification-title">${stamp(x.closed?'相关事项已核结':x.urgent?'出港前待办':x.read?'已读':'未读')}<h3>${ui.e(x.title)}</h3></div><p>${ui.e(x.body||'这项变化已留入本航记录。')}</p><span class="small muted">${x.closed?'已结事项留档回看，不重复执行原动作。':x.read?'记录仍可回看；相关事项是否办完须看原页。':'读后可以标记，记录不会被删除。'}</span></div><div class="lp-notification-actions">${x.pageId?ui.go(x.pageId,x.closed?'查看留档凭据':'回到相关事项','button'):''}${!x.read?action(ui,'mark-notification',demo?'样例不写入已读':'标记已读','button subtle',{id:x.id},Boolean(demo)):''}</div></li>`).join(''):empty(ui,'没有符合条件的消息',readFilter==='read'?'尚无标记已读的记录。读完消息后，可将它移入此册。':'完成一笔交易、寄出家信或承接委托，实际变更会留在这里。','port-hub','去港口办理一件事')}</ol>`;
  }

  const renderers = {
    'port-hub': portHub, market, 'trade-order': tradeOrder, 'contract-board': contractBoard,
    'contract-detail': contractDetail, 'black-market': blackMarket, supplies,
    'quest-journal': questJournal, 'quest-detail': questDetail, chronicle, intelligence,
    relationships, factions: factionList, 'faction-detail': factionDetail, diplomacy,
    'sea-permits': seaPermits, 'bounty-board': bountyBoard, home, family,
    'child-growth': childGrowth, letters, 'letter-detail': letterDetail,
    'send-letter-remittance': sendLetter, 'voyage-result': voyageResult, accounts,
    tutorial, defeat, 'notification-log': notificationLog
  };

  function deriveLifeState(id, state) {
    const view = { ...state }, label = state.previewScenario;
    const fixture=()=>{view._lifeFixture=true;};
    const use = (key, value) => { if (value !== undefined && state[key] === undefined) view[key] = value; };
    if (id === 'market' && label === '急需补给') use('marketFilter', 'supplies');
    if (id === 'supplies' && label === '超出预算') use('provisionDays', 60);
    if (id === 'contract-board') {
      use('contractFilter', { '可接': 'ready', '进行中': 'accepted', '待交割': 'pending' }[label]);
      if (['进行中','待交割'].includes(label) && !acceptedContractIds(state).length) { view.acceptedContracts=['delivery'];view.selectedContract='delivery';fixture(); }
      if (label==='待交割'&&!Object.values(state.contractDeliveries||{}).includes('pending')) {const cid=acceptedContractIds(view)[0]||'delivery';view.contractDeliveries={...state.contractDeliveries,[cid]:'pending'};fixture();}
    }
    if(id==='contract-detail'&&label==='履约待验') {
      const existing=Object.keys(state.contractDeliveries||{}).find(cid=>state.contractDeliveries[cid]==='pending');
      if(existing)view.selectedContract=existing;
      else {const cid=acceptedContractIds(state)[0]||'delivery';view.selectedContract=cid;view.acceptedContracts=[...new Set([...acceptedContractIds(state),cid])];view.contractDeliveries={...state.contractDeliveries,[cid]:'pending'};for(const key of ['manifest','identity','loss'])view[`contract-evidence-${cid}-${key}`]=true;fixture();}
    }
    if(id==='contract-detail'&&label==='欠损未清'&&!state.selectedContract)view.selectedContract='delivery';
    if (id === 'quest-journal') use('journalFilter', { '当前主线': 'main', '待交割': 'contracts', '承诺未清': 'promise', '已完成': 'done' }[label]);
    if (id === 'intelligence') use('intelFilter', { '未经核实': 'unverified', '相互印证': 'confirmed', '已证伪': 'disproved', '已过时': 'expired' }[label]);
    if (id === 'chronicle') { use('chronicleKind', { '历史节点':'history','跨年概括':'cross','原创航次':'story' }[label]); if (label === '当前年份') use('chronicleYear','1624'); }
    if (id === 'relationships' && ['旧恩未偿', '关系破裂', '有限缓和'].includes(label)) use('selectedPerson', 'duqi');
    if (id === 'factions' && ['通路受制', '交战'].includes(label)) use('factionScope', 'coast');
    if (id === 'factions' && label === '交战') use('selectedFaction', 'armed');
    if (id === 'factions' && label === '临时结盟') use('selectedFaction','fujian');
    if (id === 'diplomacy' && label === '身份改变') use('selectedFaction','fujian');
    if (id === 'sea-permits') use('selectedPermit', { '不被对方承认': 'commission', '旗号冒用': 'flag', '凭据已毁': 'commission' }[label]);
    if (id === 'family') use('familyYear', { '成家': '约1622／1623', '隔海抚育': '1624', '迎子赴明': '1630', '各有决定': '1646' }[label]);
    if (id === 'child-growth') use('childYear', { '幼年平户': '1624', '赴明蒙学': '1630', '求学成长': '求学', '领受职分': '1645' }[label]);
    if (id === 'letters') use('letterFilter', { '已收到': 'received', '已写未托': 'draft', '随船在途': 'sent', '送达不明': 'unknown' }[label]);
    if (id === 'letter-detail' && label === '附船图童谣') { view.letterFilter = 'received'; view.selectedLetter = 'boat'; }
    if (id === 'letter-detail' && label === '寄款附记') {
      view.letterFilter='sent';
      if(sentRecords(state).length)view.selectedLetter=sentRecords(state)[0].id;
      else {view.sentLetterRecords=[{id:'preview-remittance',title:'安排与随信家用 · 只读样例',recipient:'田川氏',body:'家中：\n\n下一航已经应下，回平户的船我没有同行。这次随信附家用一百二十两，捎信费用另付。\n\n归期尚未定，之后的安排会再托陈添写明。银已交托也仍须等收到的回音，不能说成我已经回去。',amount:120,date:'1624年 · 情境样例',fixture:true}];view.selectedLetter='preview-remittance';fixture();}
    }
    if(id==='tutorial'&&label==='随时重看'){use('tutorialTopic','letters');use('tutorialStep',2);}
    if(id==='tutorial'&&label==='已学会'){
      use('tutorialStep',3);
      const learnedKey=`tutorial-learned-${view.tutorialTopic||'helm'}`;
      if(state[learnedKey]===undefined){view[learnedKey]=true;fixture();}
    }
    if (id === 'send-letter-remittance' && label === '待写') use('letterDraft', '');
    if (id === 'accounts') use('accountTab', { '欠款未清': 'owed', '家用被挪': 'owed' }[label]);
    if (id === 'notification-log' && label === '已读') use('notificationRead', 'read');
    return view;
  }
  function lifeSupplement(id, state, ui) {
    if (id === 'quest-detail') return `<section class="lp-quest-evidence"><div><h3>完成凭据</h3><strong>${sentRecords(state).length ? '已有实际托寄记录' : '尚无本次托寄记录'}</strong><p>追踪只把事情留在眼前；正文与附银须在寄件和账房中另有记录。</p></div><div><h3>相关的人与地点</h3><p>田川氏在平户，阿旺在船上；陈添问明回船，归期仍由一官照实答复。</p><div class="toolbar">${ui.go('relationships','回看各自诉求','button')}${ui.go('intelligence','核回船消息','button')}</div></div><div><h3>不可抹去的代价</h3><p>应下下一航与错过回家机会来自本场正线。后来寄出的信与银，不会把那些日子改写成团聚。</p></div></section>`;
    if (id === 'letter-detail') {
      const rows = visibleLetters(state), selected = rows.find(x => x.id === String(state.selectedLetter)) || rows[0];
      return `<section class="lp-reader-appendix"><div><h3>${selected?.id === 'boat' ? '附物与一段学唱的调子' : selected?.personal ? '随信银与托话人' : '准备回信时，先回答这几句'}</h3><p>${selected?.id === 'boat' ? '母亲画了船身，空处留给孩子长大自己添。歌的读音另有托话，不把本页相关剧情插图冒称传世信件原物。' : selected?.personal ? `${selected.fixture?'示例附银':'实际附银'}${n(selected.amount)}两，捎信费另记20两。交给托话人后，还要等回音。` : '后面要去哪里、已经应下哪一航、下一次托话经过谁。未定的事，也照实写。'}</p></div><div>${ui.go('send-letter-remittance','把未答复的事写明','button')}${ui.go('accounts','信与家用另核一笔','text-button')}</div></section>`;
    }
    return '';
  }
  window.GameUI.registerRenderer(Object.keys(renderers), (screen, state, ui) => {
    const id = typeof screen === 'string' ? screen : screen.id;
    const view = deriveLifeState(id, state);
    const rendererUI=view._lifeFixture?{...ui,action:(name,label,cls,attrs)=>{
      const html=ui.action(name,label,cls,attrs);
      return ['accept-contract','deliver-contract','buy','sell','send-letter','load','accept-quest','toggle'].includes(name)?html.replace('<button','<button disabled aria-disabled="true" title="只读情境样例，不写入真实记录"'):html;
    }}:ui;
    const fixtureCaption=view._lifeFixture?'<div class="lp-fixture-caption">只读情境样例 · 本次没有对应实际记录。下方示例凭据不写入库存、现银、日志或寄件。</div>':'';
    const readerTools = id === 'letter-detail' ? `<div class="lp-reader-tools"><span>纸面阅读</span>${set(ui,'letterText',state.letterText==='large'?'normal':'large',state.letterText==='large'?'恢复正文字号':'放大正文','button subtle')}${ui.go('letters','返回信袋','text-button')}</div>` : '';
    return `<div class="life-screen life-${id} ${state.letterText==='large'?'lp-letter-large':''}" data-life-scenario="${ui.e(state.previewScenario||'正常')}">${scenarioSurface(id,state,ui)}${readerTools}${fixtureCaption}${renderers[id](view, rendererUI)}${lifeSupplement(id,view,rendererUI)}</div>`;
  });
})();
