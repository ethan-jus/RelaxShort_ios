import Foundation

// MARK: - Mock API Repository
/// 30部真实短剧数据（董事长提供：标题+封面+视频）

// MARK: - Shared Constants

private enum MC {
    static let delay: UInt64 = 800_000_000

    /// 30部真实短剧数据 (标题, 封面, 视频)
    static let dramas: [(title: String, cover: String, video: String)] = [
        ("江南时节",    "http://cdn.bjyoushi.top/images/JIANG-NAN-SHI-JIE/2025/03/12/20250312125604MKUt0.jpg",    "http://cdn.bjyoushi.top/videos/JIANG-NAN-SHI-JIE/2025/03/12/20250312125604XjeM1.mp4"),
        ("今日离港有雪", "http://cdn.bjyoushi.top/images/JIN-RI-LI-GANG-YOU-XUE/2025/03/12/20250312175226sWvf0.jpg", "http://cdn.bjyoushi.top/videos/JIN-RI-LI-GANG-YOU-XUE/2025/03/12/20250312175227bSwB1.mp4"),
        ("掌心难逃",    "http://cdn.bjyoushi.top/images/ZHANG-XIN-NAN-TAO/2025/03/12/20250312180615LNcP0.jpg",    "http://cdn.bjyoushi.top/videos/ZHANG-XIN-NAN-TAO/2025/03/12/20250312180615EUPL1.mp4"),
        ("好一个乖乖女", "http://cdn.bjyoushi.top/images/HAO-YI-GE-GUAI-GUAI-NV/2025/03/12/20250312211835HZVV0.jpg", "http://cdn.bjyoushi.top/videos/HAO-YI-GE-GUAI-GUAI-NV/2025/03/12/20250312211835TRut1.mp4"),
        ("闪婚老伴是豪门","http://cdn.bjyoushi.top/images/SHAN-HUN-LAO-BAN-SHI-HAO-MEN/2025/03/12/20250312221936Fctg0.png","http://cdn.bjyoushi.top/videos/SHAN-HUN-LAO-BAN-SHI-HAO-MEN/2025/03/12/20250312221936OpLg1.mp4"),
        ("她走后京圈太子爷急疯了","http://cdn.bjyoushi.top/images/TA-ZOU-HOU-JING-QUAN-TAI-ZI-YE-JI-FENG-LE/2025/03/12/20250312225254dtbm0.jpg","http://cdn.bjyoushi.top/videos/TA-ZOU-HOU-JING-QUAN-TAI-ZI-YE-JI-FENG-LE/2025/03/12/20250312225254dWDX1.mp4"),
        ("咬清梨",      "http://cdn.bjyoushi.top/images/YAO-QING-LI/2025/03/12/20250312234012SshS0.png",          "http://cdn.bjyoushi.top/videos/YAO-QING-LI/2025/03/12/20250312234012tlpF1.mp4"),
        ("未来日记",    "http://cdn.bjyoushi.top/images/WEI-LAI-RI-JI/2025/03/12/20250312235036kCIY0.jpg",       "http://cdn.bjyoushi.top/videos/WEI-LAI-RI-JI/2025/03/12/20250312235036hLqf1.mp4"),
        ("坠入春夜",    "http://cdn.bjyoushi.top/images/ZHUI-RU-CHUN-YE/2025/03/13/20250313000050hmyO0.jpg",      "http://cdn.bjyoushi.top/videos/ZHUI-RU-CHUN-YE/2025/03/13/20250313000050mdze1.mp4"),
        ("穆总的天价小新娘","http://cdn.bjyoushi.top/images/MU-ZONG-DE-TIAN-JIA-XIAO-XIN-NIANG/2025/03/13/20250313164352uzfm0.jpg","http://cdn.bjyoushi.top/videos/MU-ZONG-DE-TIAN-JIA-XIAO-XIN-NIANG/2025/03/13/20250313164352aYBy1.mp4"),
        ("声色犬马",    "http://cdn.bjyoushi.top/images/SHENG-SE-QUAN-MA/2025/03/13/20250313181039kDxO0.jpeg",    "http://cdn.bjyoushi.top/videos/SHENG-SE-QUAN-MA/2025/03/13/20250313181040elny1.mp4"),
        ("荣归",        "http://cdn.bjyoushi.top/images/RONG-GUI/2025/03/14/20250314103234hXqV0.jpg",             "http://cdn.bjyoushi.top/videos/RONG-GUI/2025/03/14/20250314103234GlJw1.mp4"),
        ("引她入室",    "http://cdn.bjyoushi.top/images/YIN-TA-RU-SHI/2025/03/14/20250314104057OREQ0.jpg",        "http://cdn.bjyoushi.top/videos/YIN-TA-RU-SHI/2025/03/14/20250314104057xLDx1.mp4"),
        ("来不及说再见","http://cdn.bjyoushi.top/images/LAI-BU-JI-SHUO-ZAI-JIAN/2025/03/14/20250314110514gaWI0.jpg","http://cdn.bjyoushi.top/videos/LAI-BU-JI-SHUO-ZAI-JIAN/2025/03/14/20250314110514Fnym1.mp4"),
        ("黑月光之重启人生","http://cdn.bjyoushi.top/images/HEI-YUE-GUANG-ZHI-ZHONG-QI-REN-SHENG/2025/03/14/20250314111537jTse0.jpg","http://cdn.bjyoushi.top/videos/HEI-YUE-GUANG-ZHI-ZHONG-QI-REN-SHENG/2025/03/14/20250314111537uEds1.mp4"),
        ("风云再起&痴傻老爸竟是仙人","http://cdn.bjyoushi.top/images/FENG-YUN-ZAI-QI-&-CHI-SHA-LAO-BA-JING-SHI-XIAN-REN/2025/03/14/20250314113253LnWY0.jpg","http://cdn.bjyoushi.top/videos/FENG-YUN-ZAI-QI-&-CHI-SHA-LAO-BA-JING-SHI-XIAN-REN/2025/03/14/20250314113253laMq1.mp4"),
        ("少帅的笼中鸟","http://cdn.bjyoushi.top/images/SHAO-SHUAI-DE-LONG-ZHONG-NIAO/2025/03/14/20250314113817GJhG0.jpg","http://cdn.bjyoushi.top/videos/SHAO-SHUAI-DE-LONG-ZHONG-NIAO/2025/03/14/20250314161842lNWP1.mp4"),
        ("将魂",        "http://cdn.bjyoushi.top/images/JIANG-HUN/2025/03/14/20250314121722pUxL0.jpg",              "http://cdn.bjyoushi.top/videos/JIANG-HUN/2025/03/14/20250314121722vsQP1.mp4"),
        ("情靡",        "http://cdn.bjyoushi.top/images/QING-MI/2025/03/14/20250314122449TyPS0.jpg",              "http://cdn.bjyoushi.top/videos/QING-MI/2025/03/14/20250314122449cGLk1.mp4"),
        ("逆鳞",        "http://cdn.bjyoushi.top/images/NI-LIN/2025/03/14/20250314130218teFB0.jpg",               "http://cdn.bjyoushi.top/videos/NI-LIN/2025/03/14/20250314130218ZAHz1.mp4"),
        ("玉山初盛",    "http://cdn.bjyoushi.top/images/YU-SHAN-CHU-SHENG/2025/03/14/20250314130858SmdA0.jpg",     "http://cdn.bjyoushi.top/videos/YU-SHAN-CHU-SHENG/2025/03/14/20250314130858mKVj1.mp4"),
        ("爱在青山兴盛时","http://cdn.bjyoushi.top/images/AI-ZAI-QING-SHAN-XING-SHENG-SHI/2025/03/14/20250314130246Jzcg0.jpg","http://cdn.bjyoushi.top/videos/AI-ZAI-QING-SHAN-XING-SHENG-SHI/2025/03/14/20250314130247SKzs1.mp4"),
        ("请和我前夫结婚吧","http://cdn.bjyoushi.top/images/QING-HE-WO-QIAN-FU-JIE-HUN-BA/2025/03/14/20250314153256jUMH0.jpg","http://cdn.bjyoushi.top/videos/QING-HE-WO-QIAN-FU-JIE-HUN-BA/2025/03/14/20250314153256yfGs1.mp4"),
        ("乡村重生之出人头地","http://cdn.bjyoushi.top/images/XIANG-CUN-ZHONG-SHENG-ZHI-CHU-REN-TOU-DI/2025/03/14/20250314162152htVg0.jpg","http://cdn.bjyoushi.top/videos/XIANG-CUN-ZHONG-SHENG-ZHI-CHU-REN-TOU-DI/2025/03/14/20250314162152WrbU1.mp4"),
        ("舔女神三年我无敌了","http://cdn.bjyoushi.top/images/TIAN-NV-SHEN-SAN-NIAN-WO-WU-DI-LE/2025/03/14/20250314164733JPxG0.jpg","http://cdn.bjyoushi.top/videos/TIAN-NV-SHEN-SAN-NIAN-WO-WU-DI-LE/2025/03/14/20250314164733PxFs1.mp4"),
        ("穿到古代当首富","http://cdn.bjyoushi.top/images/CHUAN-DAO-GU-DAI-DANG-SHOU-FU/2025/03/14/20250314170915LbkF0.jpg","http://cdn.bjyoushi.top/videos/CHUAN-DAO-GU-DAI-DANG-SHOU-FU/2025/03/14/20250314170915ZgDh1.mp4"),
        ("逆袭1990",    "http://cdn.bjyoushi.top/images/NI-XI-1-9-9-0/2025/03/14/20250314180028XjFP0.jpg",        "http://cdn.bjyoushi.top/videos/NI-XI-1-9-9-0/2025/03/14/20250314180028FtTE1.mp4"),
        ("暮色不及你难忘","http://cdn.bjyoushi.top/images/MU-SE-BU-JI-NI-NAN-WANG/2025/03/18/20250318121744xoAe0.jpg","http://cdn.bjyoushi.top/videos/MU-SE-BU-JI-NI-NAN-WANG/2025/03/18/20250318121744FllJ1.mp4"),
        ("时总,夫人又忘记你们领证啦","http://cdn.bjyoushi.top/images/SHI-ZONG-,-FU-REN-YOU-WANG-JI-NI-MEN-LING-ZHENG-LA/2025/03/14/20250314185600QAiF0.jpg","http://cdn.bjyoushi.top/videos/SHI-ZONG-,-FU-REN-YOU-WANG-JI-NI-MEN-LING-ZHENG-LA/2025/03/14/20250314185600sscZ1.mp4"),
        ("绝代双娇细雨楼$与君行","http://cdn.bjyoushi.top/images/JUE-DAI-SHUANG-JIAO-XI-YU-LOU-$-YU-JUN-XING/2025/03/14/20250314191127Mdby0.jpg","http://cdn.bjyoushi.top/videos/JUE-DAI-SHUANG-JIAO-XI-YU-LOU-$-YU-JUN-XING/2025/03/14/20250314191127DouF1.mp4"),
    ]
}

/// 剧集分类
private let categories: [(String, [String])] = [
    ("现代言情", ["romance","modern","drama"]),
    ("总裁",     ["romance","ceo","billionaire"]),
    ("逆袭",     ["revenge","strong","comeback"]),
    ("古代言情", ["ancient","romance","costume"]),
    ("甜宠",     ["sweet","romance","comedy"]),
    ("豪门恩怨", ["family","billionaire","drama"]),
    ("玄幻",     ["fantasy","immortal","myth"]),
    ("马甲",     ["mystery","hidden-identity","power"]),
]

/// 简介模板（约300字）
private let synopses = [
    "在这个繁华都市的某个角落，一个平凡的女孩正在经历一场命运的巨变。她叫林微，二十三岁，刚从名牌大学毕业，却在求职路上四处碰壁。生活的压力让她几乎喘不过气来，直到那天晚上，她在回家的路上遇到了那个改变她一生的男人。他西装革履，气质非凡，却倒在了雨夜的街头。林微没有多想，撑着伞走了过去，就是这个决定让她卷入了一场豪门恩怨的旋涡之中。她不知道的是，这个倒在她面前的男人正是京城最有权势的沈家长子沈霁寒，而他背后隐藏的秘密将彻底颠覆她的人生。",

    "前世她是被渣男贱女联手害死的商界女帝，含恨而终再睁眼回到二十岁，一切尚未发生的那个夏天。这一次她要亲手改写命运，撕开伪善者的面具，夺回属于自己的一切。她手握前世积累的商业智慧，步步为营布局整个商界，让曾经的仇人一个个跪地求饶。然而当她以为一切尽在掌控时，那个前世从未在她生命中出现过的男人突然现身，他看她的眼神里藏着千年的秘密，似乎早已预知她的归来。命运的齿轮重新开始转动，而这一次结局将完全不同。",

    "苏雨桐从未想过，自己的婚姻会始于一场替嫁。姐姐在婚礼前夜逃婚，为了家族颜面，父亲逼她披上嫁衣嫁入传说中冷酷无情的霍家。新婚夜她第一次见到霍司寒，那个传说中心狠手辣的男人却对着她露出温柔的笑容。婚后他宠她入骨为她遮风挡雨，让她以为自己嫁进了蜜罐。直到某天她无意中翻开他的秘密书房，才发现墙壁上贴满了姐姐的照片，而她不过是姐姐的影子。原来这场替嫁从一开始就是一场精心策划的阴谋，她只是他报复计划中的一枚棋子。",

    "传闻镇北侯世子容貌尽毁性情暴戾，朝中无人敢嫁。顾清欢接旨赐婚那天，整个京城都在替她惋惜。她抱着赴死的心踏进侯府，却发现传闻中可怕的世子沈墨寒不仅容颜未毁，反而生得天人之姿。他教她骑射带她看遍边关风月，在漫天星河下许她一世长安。然而朝中暗流涌动，沈墨寒被诬通敌叛国，圣旨赐下鸩酒之时，顾清欢挡在他身前饮下毒酒。临死前她附在他耳边轻语若有来生我还要做你的妻。三年后边境大军中，一名戴着银色面具的女将横空出世，她率领的军队战无不胜，直指京城。",

    "叶清辞十六岁那年被亲生母亲赶出家门，原因无他只因她是叶家的私生女。自那之后她沦落街头尝尽人间冷暖，直到遇上那个愿意收留她的老中医。她发奋学医十年磨一剑，终于成为国内最年轻的医学教授。然而命运弄人，她接诊的第一个VIP病人竟是当年抛弃她的生母。母亲得了罕见重病需要直系亲属配型移植，而叶家长子和长女全部不匹配。病房外父亲跪地痛哭求你救救她她毕竟是你亲妈。叶清辞站在手术室门前沉默良久，然后轻声笑了出来。",

    "容屿三十岁封神是整个娱乐圈的神话，影帝视帝一身光环无人能及。他从不参加综艺不炒绯闻，冷酷得像个没有感情的机器人。直到《星空下的旅程》这档综艺横空出世，节目组安排了一个素人小姑娘当他的七日导游。她叫唐小暖今年十八岁，笑起来眼睛弯成月牙不知道什么是收敛什么是分寸，第一天就踩了他的鞋泼了他一身水拉着他跳广场舞。容屿全程黑脸全网嘲讽，却在第七天节目直播中被拍到死攥着她的手腕不放。弹幕瞬间炸了容影帝你手放哪儿呢这是全网直播。",

    "南乔穿书了，穿进一本狗血虐文成了恶毒女配。原书中她作死不断，活活作到最后一集被男主凌迟处死。她决定摆烂佛系，转头看上了书中出场仅三页就领盒饭的工具人男配顾衍生。他在原著中被一笔带过，却偏偏生得人畜无害笑起来像个温暖的小太阳。南乔把他捡回家养着他宠着他保护他，只求他这辈子能活得久一点。可当她带他去参加宫廷宴会，当朝最尊贵的那个人从龙椅上走下来单膝跪地喊了一声主人。全场死寂顾衍生回头冲她一笑，南乔手里的酒杯掉在了地上。",

    "江暖当了三年全职太太，换来的是丈夫冷冰冰的四个字我们离婚吧。理由很大方他出轨了，娶了她最信任的闺蜜。她净身出户连住的地方都没有，只能带着三岁的女儿住进城中村的地下室。就在人生最低谷的时候她遇到了一个奇怪的小女孩，小女孩天天来她摊前蹭吃蹭喝，身后跟着一群西装革履的黑衣人。直到女孩的父亲突然出现，那个冷峻矜贵的男人盯着她的脸看了很久，然后用难以置信的声音颤抖地问江念念是你吗。她愣了，那是她六岁之前的小名，这个人是谁他怎么会知道。",

    "陆时砚是业内有名的金牌律师出道十年未尝一败，冷峻疏离从不对任何当事人动感情。直到一个名叫秦小满的女孩推开他办公室的门，她抱着一沓皱巴巴的材料眼眶通红，说我要告我亲生父亲他偷了我妈妈的公司害我妈妈含恨离世。对方请的律师是陆时砚的师兄业界最顶尖的辩护人，所有人都劝秦小满放弃，但她摇头看着她倔强的背影，陆时砚第一次破了自己的规矩。他从高楼大厦走下去追到她的出租屋门口，在那一室的凌乱与破败中他看见墙壁上贴满了她妈妈的判决书资料，看见她守了三年都没放弃的信念。",

    "林朝雨第一次见薄砚是在深冬的长街，男人穿一件黑色风衣靠在劳斯莱斯旁，俊美矜贵不似真人。她说先生能不能借我两百块我打车，他看了她一眼丢给她一张黑卡。她以为遇上好人，结果第二天一纸合约送到她面前薄先生需要你做他一年的未婚妻。作为交换条件他为她还清所有债务，条件是把戏演好不准假戏真做。她咬牙签了约，搬进他的别墅开始扮演他的未婚妻。他待她极好珠宝名包应有尽有，只是从不多看她一眼。直到合约最后一天她收拾行李准备离开，他从背后抱住她把脸埋进她的颈窝，声音沙哑地说我反悔了你要什么我都给。",

    "宋时微醒来的时候发现自己躺在乱葬岗，身上盖着白布四周阴风怒号。她记得自己上一刻还在大殿受封皇后，下一刻就被一碗毒酒送了命。她爬出乱葬岗用三年时间改头换面以新的身份入宫，这一次她要让那个负心人和那个毒妇付出代价。她步步为营在后宫掀起惊涛骇浪，皇帝被她迷得神魂颠倒不知道自己怀里搂着的是三年前的冤魂。然而计划进行到最后一步时，那个一向沉默寡言的摄政王忽然挡在她面前对皇帝说这个女人碰不得她是我的王妃。宋时微愕然她根本不认识他。摄政王转过头对她一笑，轻声说殿下三年前我就想这么叫你了。",

    "简星燃作为电竞圈第一天才中单选手，拿下过三次世界冠军身价过亿，却因为一次转会风波被全网唾骂。队友背叛粉丝脱粉，他从神坛跌入谷底。在所有人等着看笑话的时候，一个名不见经传的新战队向他伸出了手。队长是一个比他小两岁的少年叫许晏，笑起来有些腼腆说简哥我从十三岁开始看你的比赛，我相信你。简星燃冷笑着拒绝了，但许晏没有放弃一次又一次地找他，在网吧陪他通宵训练在赛场外替他挡下谩骂，在他喝醉的时候背他回家。等到简星燃终于点头加入，他才发现这支新战队里藏着的不只是许晏的热情，还有一个他找了十年的秘密。",

    "沈昔年在十九岁大婚那晚，亲眼看着她的新郎亲手捅了她一刀。他擦干净匕首对身边的女人说处理干净别留痕迹。她被推进后山的冰湖里，冷水和剧痛吞噬着她的意识。她本以为就此结束，却在一个月后以新的身份醒了过来。这一次她拥有了逆天的医毒之术，随手一针可救人一命亦可杀人无形。她回到凤京城改头换面，成了新开张药铺的女掌柜。当年害她的人一个个死于非命，京城人心惶惶。当大理寺卿萧怀远找上门来查案时，她笑着递上一杯茶说大人您要查的人就站在你面前。萧怀远低头看着杯中的倒影，他笑起来说我知道我一直在等你回来。",

    "季晚晚嫁入傅家三年，做过最奢侈的事就是在菜市场多买了二两排骨。她被婆婆嫌弃被小姑子使唤被丈夫无视，每天活得像个透明人。她不是没有脾气，只是为了当初的承诺她一忍再忍。直到有天她在厨房切菜，电视里正在播放一则寻人启事播音员的声音里带着急切季家小女季晚晚三年前走失，季家悬赏十亿寻找。她愣住手里的刀滑落在地。当天下午十辆劳斯莱斯开进傅家所在的小区，西装革履的男人从车上下来扑通跪在她面前，眼眶发红地喊了一声大小姐我们来接您回家。傅家人全都惊呆在门口一句话也说不出来。",

    "苏念生活里只有两件事刷题和还债。父亲去世留下两百万的债务，她靠当家教和打零工维持学业。直到她碰上班里最不好惹的学生周野。他是临城一中有名的校霸打架逃课抽烟喝酒，据说他爸是道上的人没人敢管。苏念第一次去他家补课就被他轰了出去，但她没走站在门口讲了整整一个小时的数学题。周野拉开门瞪着她你是不是有病。她不急不慢地说题目都没教完，家长付了钱我不能糊弄。后来不知道从哪天开始，那个谁都不服的少年开始按时上课认真写作业，每天放学都守在校门口等她。他说苏老师我想考你那所大学，你等我。他说话的时候耳尖微红眼神是从未有过的认真。",
]

private func d(_ idx: Int) -> DramaItem {
    let data = MC.dramas[idx]
    let catIdx = idx % categories.count
    let cat = categories[catIdx]
    let viewCounts: [Int] = [5_500_000, 607_000, 1_600_000, 318_000, 1_370_000,
                               890_000, 420_000, 670_000, 1_200_000, 1_150_000,
                               172_000, 430_000, 1_080_000, 717_000, 628_000,
                               2_390_000, 619_000, 3_500_000, 1_900_000, 4_800_000,
                               2_700_000, 5_100_000, 7_300_000, 1_850_000, 9_400_000,
                               3_300_000, 10_500_000, 2_800_000, 4_500_000, 8_600_000]
    let episodes = [53,44,41,70,77,60,48,55,42,36,30,52,40,38,46,58,34,50,45,62,
                    48,56,44,52,38,60,42,48,36,50]

    return DramaItem(
        id: String(idx + 1),
        title: data.title,
        coverURL: data.cover,
        videoURL: data.video,
        category: cat.0,
        tags: cat.1,
        viewCount: viewCounts[idx],
        episodeCount: episodes[idx],
        currentEpisode: 0,
        synopsis: synopses[idx % synopses.count],
        isHot: idx < 8,
        isTrending: idx >= 4 && idx < 15,
        rating: Double(85 + (idx % 15)) / 10.0,
        coinReward: 30 + (idx % 6) * 20,
        imageHeight: 160 + CGFloat(idx % 10) * 10,
        badge: idx < 3 ? .hot : (idx < 6 ? .new : (idx < 9 ? .vip : nil))
    )
}

// MARK: - Mock Data

enum MockData {
    static let dramas: [DramaItem] = (0..<30).map { d($0) }

    static let banners: [BannerItem] = [
        BannerItem(id: "b_1", title: MC.dramas[0].title, imageName: MC.dramas[0].cover, tags: ["Hot","CEO"],     dramaId: "1"),
        BannerItem(id: "b_2", title: MC.dramas[3].title, imageName: MC.dramas[3].cover, tags: ["New","Sweet"],   dramaId: "4"),
    ]

    static func episodes(for dramaId: String) -> [Episode] {
        let dramaIdx = (Int(dramaId) ?? 1) - 1
        let baseVideo = MC.dramas[dramaIdx % MC.dramas.count].video
        // 30集，每集不同 videoURL（轮换使用不同短剧视频），前3集免费
        return (1...30).map { i in
            let altIdx = (dramaIdx + i) % MC.dramas.count
            let altVideo = MC.dramas[altIdx].video
            let videoURL = i <= 3 ? baseVideo : altVideo
            return Episode(
                id: "ep_\(dramaId)_\(i)",
                dramaId: dramaId,
                episodeNumber: i,
                title: L10n.playerEpisodeNumber(i),
                videoURL: videoURL,
                duration: TimeInterval(90 + Double((i % 7) * 12)),
                isLocked: i > 3
            )
        }
    }

    static let watchHistory: [WatchHistoryItem] = {
        let m = Dictionary(uniqueKeysWithValues: dramas.map { ($0.id, $0) })
        let fallback = dramas[0]
        return [
            WatchHistoryItem(id: "w_1", drama: m["1"] ?? fallback, episodeID: "ep_1_18", currentEpisode: 18, resumeTime: 34, watchedAt: Date(), progress: 0.34),
            WatchHistoryItem(id: "w_2", drama: m["4"] ?? fallback, episodeID: "ep_4_35", currentEpisode: 35, resumeTime: 52, watchedAt: Date(), progress: 0.50),
            WatchHistoryItem(id: "w_3", drama: m["6"] ?? fallback, episodeID: "ep_6_8", currentEpisode: 8,  resumeTime: 12, watchedAt: Date(), progress: 0.13),
        ]
    }()

    static let profile = User(
        id: "u_mock_001", nickname: "ER", avatarURL: nil,
        isVip: true,
        vipExpireDate: Calendar.current.date(byAdding: .day, value: 180, to: Date()),
        coinBalance: 1280, favoriteCount: 3
    )

    static let vipPlans: [VIPPlan] = [
        VIPPlan(id: "weekly",    title: "周会员", price: "$12.99",  originalPrice: nil,   period: "/周", isRecommended: false, description: nil, dailyPrice: nil, discountPercent: nil),
        VIPPlan(id: "monthly",   title: "月会员", price: "$29.99",  originalPrice: nil,   period: "/月", isRecommended: true,  description: nil, dailyPrice: nil, discountPercent: nil),
        VIPPlan(id: "quarterly", title: "季会员", price: "$68.99",  originalPrice: "$89.99", period: "/季", isRecommended: false, description: nil, dailyPrice: nil, discountPercent: nil),
        VIPPlan(id: "yearly",    title: "年会员", price: "$199.99", originalPrice: "$299.99", period: "/年", isRecommended: false, description: nil, dailyPrice: nil, discountPercent: nil),
    ]

    static let vipBenefits: [VIPBenefit] = [
        VIPBenefit(icon: "play.rectangle.on.rectangle", title: "全集畅看"),
        VIPBenefit(icon: "speaker.slash",               title: "免广告"),
        VIPBenefit(icon: "4k.tv",                       title: "高清画质"),
        VIPBenefit(icon: "arrow.down.to.line",          title: "离线下载"),
        VIPBenefit(icon: "star",                        title: "VIP专属剧集"),
    ]

    static let checkInDays: [CheckInDay] = [
        CheckInDay(label: "今天",   coins: "+10",  checked: true),
        CheckInDay(label: "第2天",  coins: "+15",  checked: true),
        CheckInDay(label: "第3天",  coins: "+20",  checked: false),
        CheckInDay(label: "第4天",  coins: "+25",  checked: false),
        CheckInDay(label: "第5天",  coins: "+35",  checked: false),
        CheckInDay(label: "第6天",  coins: "+50",  checked: false),
        CheckInDay(label: "第7天",  coins: "+100", checked: false),
    ]

    static let coinTasks: [CoinTask] = [
        CoinTask(iconName: "calendar.badge.checkmark", title: "每日签到",   subtitle: "签到领金币",            buttonText: "去签到"),
        CoinTask(iconName: "play.rectangle",           title: "观看5分钟",  subtitle: "看剧5分钟赚金币",        buttonText: "去看剧"),
        CoinTask(iconName: "play.rectangle.fill",       title: "观看30分钟", subtitle: "看剧30分钟赚更多金币",    buttonText: "去看剧"),
        CoinTask(iconName: "square.and.arrow.up",       title: "分享短剧",  subtitle: "分享给好友一起看",        buttonText: "去分享"),
        CoinTask(iconName: "person.badge.plus",         title: "邀请好友",  subtitle: "邀请好友各得200金币",     buttonText: "去邀请"),
        CoinTask(iconName: "creditcard",                title: "首次充值",  subtitle: "首充额外赠送500金币",     buttonText: "去充值"),
        CoinTask(iconName: "checkmark.seal",            title: "看完一部剧",subtitle: "完整看完一部剧集赠送80金币",buttonText: "去看剧"),
        CoinTask(iconName: "flame",                     title: "连续签到",  subtitle: "连续签到7天额外送150金币",buttonText: "去签到"),
    ]

    // MARK: - v1 DramaBox 复刻稳定数据分组

    /// For You 推荐流 (全部30部，顺序稳定)
    static let forYouFeed: [DramaItem] = {
        var items = dramas
        for i in items.indices {
            items[i].regionTag = (i % 4 == 0) ? "China" : nil
            items[i].languageTag = (i % 3 == 0) ? "Mandarin" : nil
            items[i].freeEpisodeRange = 1...3
            items[i].coinPrice = 50 + (i % 3) * 50
        }
        return items
    }()

    /// 首页热门 (前8部，按热度)
    static let homePopular: [DramaItem] = Array(dramas.prefix(8))

    /// 首页VIP推荐 (VIP角标剧)
    static let homeVipRecommendations: [DramaItem] = {
        var items = dramas.filter { $0.badge == .vip }
        for i in items.indices {
            items[i].isVIPOnly = true
            items[i].freeEpisodeRange = 1...2
        }
        return items
    }()

    /// 首页排行榜 (按观看量降序Top5)
    static let homeRankings: [DramaItem] = Array(
        dramas.sorted(by: { $0.viewCount > $1.viewCount }).prefix(5)
    )

    /// 会员专属剧 (vip badge + isVIPOnly)
    static let memberOnlyDramas: [DramaItem] = {
        var items = dramas.filter { $0.badge == .vip }
        for i in items.indices {
            items[i].isVIPOnly = true
            items[i].isMemberOnly = true
            items[i].freeEpisodeRange = 1...2
        }
        return items
    }()

    // comingSoonDramas removed — Coming Soon UI is banned per v1 spec

    /// My List 关注列表 (标记 isFollowed 的剧)
    static let myListFollowing: [DramaItem] = {
        var items: [DramaItem] = []
        let indices = [0, 3, 7, 12, 18, 24]
        for idx in indices where idx < dramas.count {
            var d = dramas[idx]
            d.isFollowed = true
            d.regionTag = "China"
            d.languageTag = "Mandarin"
            items.append(d)
        }
        return items
    }()

    /// 扩展观看历史 (更多条目)
    static let moreWatchHistory: [WatchHistoryItem] = {
        let m = Dictionary(uniqueKeysWithValues: dramas.map { ($0.id, $0) })
        let fallback = dramas[0]
        return [
            WatchHistoryItem(id: "w_1", drama: m["1"] ?? fallback, episodeID: "ep_1_18", currentEpisode: 18, resumeTime: 34, watchedAt: Date(), progress: 0.34),
            WatchHistoryItem(id: "w_2", drama: m["4"] ?? fallback, episodeID: "ep_4_35", currentEpisode: 35, resumeTime: 52, watchedAt: Date(), progress: 0.50),
            WatchHistoryItem(id: "w_3", drama: m["6"] ?? fallback, episodeID: "ep_6_8", currentEpisode: 8, resumeTime: 12, watchedAt: Date(), progress: 0.13),
            WatchHistoryItem(id: "w_4", drama: m["11"] ?? fallback, episodeID: "ep_11_22", currentEpisode: 22, resumeTime: 78, watchedAt: Date(), progress: 0.73),
            WatchHistoryItem(id: "w_5", drama: m["8"] ?? fallback, episodeID: "ep_8_12", currentEpisode: 12, resumeTime: 22, watchedAt: Date(), progress: 0.21),
            WatchHistoryItem(id: "w_6", drama: m["15"] ?? fallback, episodeID: "ep_15_40", currentEpisode: 40, resumeTime: 96, watchedAt: Date(), progress: 0.88),
        ]
    }()

    /// 金币套餐已由 StoreKitManager.coinPackages 提供，此处不重复定义
}

// MARK: - Repository Implementations

struct MockHomeRepository: HomeRepositoryProtocol {
    func fetchDramas(category: DramaCategory) async throws -> [DramaItem] {
        try await Task.sleep(nanoseconds: MC.delay); return MockData.dramas
    }
    func fetchBanners() async throws -> [BannerItem] {
        try await Task.sleep(nanoseconds: MC.delay); return MockData.banners
    }
}

struct MockSearchRepository: SearchRepositoryProtocol {
    func fetchSuggestions() async throws -> [String] {
        try await Task.sleep(nanoseconds: MC.delay)
        return Array(MockData.dramas.prefix(6).map(\.title))
    }
    func search(query: String, cursor: String?, limit: Int) async throws -> ([DramaItem], String?, Bool) {
        try await Task.sleep(nanoseconds: MC.delay)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = MockData.dramas.filter { drama in
            drama.title.localizedCaseInsensitiveContains(trimmed) ||
            drama.category.localizedCaseInsensitiveContains(trimmed) ||
            drama.tags.contains { $0.localizedCaseInsensitiveContains(trimmed) }
        }
        let page = cursor.flatMap(Int.init) ?? 0
        let start = page * limit
        let slice = Array(all.dropFirst(start).prefix(limit))
        let hasMore = start + limit < all.count
        let nextCursor = hasMore ? "\(page + 1)" : nil
        return (slice, nextCursor, hasMore)
    }
}

struct MockDetailRepository: DetailRepositoryProtocol {
    func fetchDramaDetail(id: String) async throws -> DramaItem {
        try await Task.sleep(nanoseconds: MC.delay); return MockData.dramas.first{$0.id==id} ?? MockData.dramas[0]
    }
    func fetchEpisodes(dramaId: String) async throws -> [Episode] {
        try await Task.sleep(nanoseconds: MC.delay); return MockData.episodes(for: dramaId)
    }
    func fetchPlayAsset(episodeId: String) async throws -> PlaybackMediaSourceDTO {
        try await Task.sleep(nanoseconds: MC.delay)
        let parts = episodeId.split(separator: "_")
        guard parts.count >= 3,
              let dramaId = parts.dropFirst().dropLast().first.map(String.init),
              let episode = MockData.episodes(for: dramaId).first(where: { $0.id == episodeId }),
              let url = URL(string: episode.videoURL),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw NSError(domain: "MockDetailRepository", code: 404, userInfo: [NSLocalizedDescriptionKey: "Mock play asset not found"])
        }
        return PlaybackMediaSourceDTO(sourceType: "mp4", masterUrl: nil, fallbackMp4Url: url.absoluteString)
    }
    func fetchUnlockAccount() async throws -> EpisodeUnlockAccount {
        EpisodeUnlockAccount(balance: 100, isVIP: false)
    }
    func unlockEpisode(episodeId: String, method: EpisodeUnlockMethod) async throws -> EpisodeUnlockResult {
        EpisodeUnlockResult(unlocked: true, balanceAfter: method == .coins ? 70 : nil)
    }
    func verifyCoinPurchase(_ receipt: ApplePurchaseReceipt) async throws -> Int {
        100 + receipt.coins
    }
    func verifyVIPPurchase(_ receipt: ApplePurchaseReceipt) async throws -> EpisodeUnlockAccount {
        EpisodeUnlockAccount(balance: 100, isVIP: true)
    }
    func fetchRelatedDramas(dramaId: String) async throws -> [DramaItem] {
        try await Task.sleep(nanoseconds: MC.delay); return Array(MockData.dramas.shuffled().prefix(6))
    }
}

struct MockFavoritesRepository: FavoritesRepositoryProtocol {
    func fetchWatchHistory(cursor: String?, limit: Int) async throws
        -> CursorPage<WatchHistoryItem> {
        try await Task.sleep(nanoseconds: MC.delay)
        // Mock: 返回全部历史，不真实分页
        let history = MockData.watchHistory
        return CursorPage(items: history, nextCursor: nil, hasMore: false)
    }
    func deleteWatchHistory(seriesID: String) async throws {
        try await Task.sleep(nanoseconds: MC.delay)
    }
    func fetchBookmarks(cursor: String?, limit: Int) async throws
        -> CursorPage<DramaItem> {
        try await Task.sleep(nanoseconds: MC.delay)
        let items = Array(MockData.dramas.shuffled().prefix(8))
        return CursorPage(items: items, nextCursor: nil, hasMore: false)
    }
    func fetchBookmarkedSeriesIDs(_ seriesIDs: [String]) async throws -> Set<String> {
        try await Task.sleep(nanoseconds: MC.delay)
        // Mock: 随机返回约一半为已收藏
        return Set(seriesIDs.filter { (Int($0) ?? 0) % 2 == 0 })
    }
    func setBookmarked(_ bookmarked: Bool, seriesID: String) async throws -> Bool {
        try await Task.sleep(nanoseconds: MC.delay)
        return bookmarked
    }
    func reportProgress(_ report: WatchProgressReport) async throws {
        try await Task.sleep(nanoseconds: MC.delay)
        // no-op in mock
    }
}

struct MockProfileRepository: ProfileRepositoryProtocol {
    func fetchUserProfile() async throws -> User {
        try await Task.sleep(nanoseconds: MC.delay); return MockData.profile
    }
}

struct MockVIPRepository: VIPRepositoryProtocol {
    func fetchPlans() async throws -> [VIPPlan] {
        try await Task.sleep(nanoseconds: MC.delay); return MockData.vipPlans
    }
    func fetchBenefits() async throws -> [VIPBenefit] {
        try await Task.sleep(nanoseconds: MC.delay); return MockData.vipBenefits
    }
}

struct MockCoinRewardRepository: CoinRewardRepositoryProtocol {
    func fetchCheckInDays() async throws -> [CheckInDay] {
        try await Task.sleep(nanoseconds: MC.delay); return MockData.checkInDays
    }
    func fetchCoinBalance() async throws -> Int {
        try await Task.sleep(nanoseconds: MC.delay); return MockData.profile.coinBalance
    }
    func fetchTasks() async throws -> [CoinTask] {
        try await Task.sleep(nanoseconds: MC.delay); return MockData.coinTasks
    }
}
