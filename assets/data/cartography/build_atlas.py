"""Reproduce the bundled physical coast; run with Shapely 2.1.2 available.

rtk proxy python assets/data/cartography/build_atlas.py --shapely-path Temp/research/cartography-py
No generated geography or historical-border reconstruction is performed.
"""
from pathlib import Path
import argparse
import gzip
import hashlib
import json
import sys
import urllib.request

parser = argparse.ArgumentParser()
parser.add_argument('--shapely-path')
args = parser.parse_args()
if args.shapely_path:
    sys.path.insert(0, args.shapely_path)
import shapely
from shapely.geometry import shape, box

ROOT = Path(__file__).resolve().parent
BASE = 'https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/'
LAND_SHA = 'e874b27a51d146452be360cafb3cc50c86001074a67d534113e6534682f9826b'
PLACES_SHA = 'fd3fa867a320cbd5c5b6bb5bc550afeec2939fb2cef688e508007282a55ac42f'
BOUNDS = [92.0, -12.0, 148.0, 45.0]
TOLERANCE = 0.025

def digest(raw):
    return hashlib.sha256(raw).hexdigest()

def write_json(path, value, pretty=False):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2 if pretty else None,
                               separators=None if pretty else (',', ':')) + '\n', encoding='utf-8')

raw = gzip.decompress((ROOT / 'ne_50m_land.geojson.gz').read_bytes())
assert digest(raw) == LAND_SHA, 'Upstream land source changed; audit before rebuilding'
source = json.loads(raw)
clip = box(*BOUNDS)
polygons = []
for feature in source['features']:
    geometry = shape(feature['geometry'])
    if not geometry.intersects(clip):
        continue
    geometry = geometry.intersection(clip).simplify(TOLERANCE, preserve_topology=True)
    for polygon in ([geometry] if geometry.geom_type == 'Polygon' else geometry.geoms):
        if polygon.geom_type != 'Polygon' or polygon.area < 0.002:
            continue
        # Physical land exterior is enough at this scale; inland-water holes
        # are intentionally omitted and documented, never sold as navigation.
        points = [[round(x, 6), round(y, 6)] for x, y in list(polygon.exterior.coords)[:-1]]
        if len(points) >= 3:
            polygons.append(points)
polygons.sort(key=lambda p: (-len(p), p[0]))
data = {'schemaVersion': 1, 'coordinateSystem': 'EPSG:4326', 'bounds': BOUNDS,
        'source': 'Natural Earth 50m physical land', 'sourceSha256': LAND_SHA,
        'simplificationDegrees': TOLERANCE, 'polygons': polygons}
write_json(ROOT / 'east_asia_land.json', data)

places_cache = ROOT / 'selected_natural_earth_places.json'
if places_cache.exists():
    selected = json.loads(places_cache.read_text(encoding='utf-8'))
else:
    raw_places = urllib.request.urlopen(BASE + 'ne_10m_populated_places_simple.geojson').read()
    assert digest(raw_places) == PLACES_SHA, 'Upstream places changed; audit before rebuilding'
    wanted = {'Macau', 'Xiamen', 'Quanzhou', 'Tainan', 'Naha', 'Manila', 'Malacca', 'Jakarta'}
    selected = [f for f in json.loads(raw_places)['features'] if f['properties']['name'] in wanted]
    assert len(selected) == len(wanted)
    write_json(places_cache, selected, pretty=True)

ports_meta = {
    'Macau': ('macau', '澳门', '香山澳', '岭南沿岸', '南海航路的门户。货栈、通事与舶来货在此相遇。'),
    'Xiamen': ('xiamen', '厦门', '中左所', '福建沿岸', '面对金门的福建港湾；近海岛屿、湾口和外洋彼此相接。'),
    'Quanzhou': ('quanzhou', '泉州', '刺桐岸', '福建沿岸', '沿海商路向内陆延伸，瓷器、丝货与乡音随船往返。'),
    'Tainan': ('dayuan', '大员', '台湾西南', '台湾海峡', '隔着海峡与福建相望。此点定位台南区域，古代沙洲和泊地另待考。'),
    'Naha': ('naha', '那霸', '琉球', '琉球群岛', '岛链处于东海与大洋之间，是辨认东洋航路的重要地理节点。'),
    'Manila': ('manila', '吕宋', '马尼拉', '南海东缘', '吕宋西岸的港市；北望台湾，西向南海。'),
    'Malacca': ('malacca', '满剌加', '海峡之口', '南洋航路', '马来半岛与苏门答腊之间，海峡把南海与印度洋连在一起。'),
    'Jakarta': ('java', '爪哇', '岛屿北岸', '南洋群岛', '此点定位今雅加达区域，供辨认爪哇岛北岸，不等同某年古港泊位。')
}
ports = []
for feature in selected:
    props = feature['properties']
    pid, name, subtitle, region, description = ports_meta[props['name']]
    lon, lat = feature['geometry']['coordinates']
    ports.append({'id': pid, 'name': name, 'subtitle': subtitle, 'region': region,
                  'description': description, 'lon': lon, 'lat': lat,
                  'source': 'Natural Earth 10m populated places', 'sourceId': str(props['ne_id']),
                  'sourceName': props['name'], 'precision': '城市区域定位，非古代泊位'})
ports.append({'id': 'hirado', 'name': '平户', 'subtitle': '九州西岸', 'region': '东洋航路',
              'description': '九州西北海面上的港湾，与川内浦相邻。此点采用长崎县平户港测站地理坐标。',
              'lon': round(129 + 33 / 60 + 18 / 3600, 6),
              'lat': round(33 + 22 / 60 + 17 / 3600, 6),
              'source': '长崎県 測定地点一覧表 PDF page 25', 'sourceId': '620-1',
              'sourceName': '平戸港', 'precision': '现代港区测站，非十七世纪泊位'})
order = ['macau', 'xiamen', 'quanzhou', 'dayuan', 'hirado', 'naha', 'manila', 'malacca', 'java']
ports.sort(key=lambda p: order.index(p['id']))
labels = [
    ['大 明', 107.0, 34.0, 35], ['朝 鲜', 126.7, 40.0, 21], ['日 本', 138.0, 37.0, 26],
    ['琉 球', 129.0, 25.7, 19], ['安 南', 105.1, 19.4, 19], ['暹 罗', 100.0, 15.5, 21],
    ['吕 宋', 124.5, 17.5, 21], ['婆 罗 洲', 114.0, 1.3, 22], ['苏 门 答 腊', 101.0, -1.8, 18],
    ['爪 哇', 111.2, -7.6, 21], ['东 海', 125.5, 30.2, 20], ['南 海', 114.5, 14.3, 29],
    ['东 洋', 137.0, 19.0, 27], ['西 洋', 94.6, 4.0, 21]
]
write_json(ROOT / 'atlas_places.json', {'schemaVersion': 1, 'ports': ports, 'labels': labels}, pretty=True)
provenance = {
    'schemaVersion': 1, 'retrievedDate': '2026-10-26', 'license': 'Public domain (Natural Earth)',
    'terms': 'https://www.naturalearthdata.com/about/terms-of-use/',
    'land': {'page': 'https://www.naturalearthdata.com/downloads/50m-physical-vectors/50m-land/',
             'rawUrl': BASE + 'ne_50m_land.geojson', 'rawSha256': LAND_SHA, 'rawBytes': len(raw),
             'retainedSource': 'ne_50m_land.geojson.gz', 'outputSha256': digest((ROOT / 'east_asia_land.json').read_bytes())},
    'places': {'page': 'https://www.naturalearthdata.com/downloads/10m-cultural-vectors/10m-populated-places/',
               'rawUrl': BASE + 'ne_10m_populated_places_simple.geojson', 'rawSha256': PLACES_SHA,
               'retainedSubset': 'selected_natural_earth_places.json', 'positionField': 'geometry.coordinates',
               'note': 'Some latitude/longitude properties differ from geometry. The actual GeoJSON Point geometry is retained.'},
    'hirado': {'url': 'https://www.pref.nagasaki.jp/uploads/2022/03/1646357182.pdf',
               'pdfPage': 25, 'printedPage': 21, 'station': '620-1 平戸港',
               'latitudeDms': '33 22 17.0 N', 'longitudeDms': '129 33 18.0 E', 'datum': '世界測地系',
               'note': 'Geographic point fact used; government PDF artwork/text not redistributed.'},
    'pipeline': {'tool': 'Shapely', 'version': shapely.__version__, 'clip': BOUNDS,
                 'simplifyDegrees': TOLERANCE, 'preserveTopology': True, 'minimumAreaDegreesSquared': 0.002,
                 'roundDecimals': 6, 'polygonCount': len(polygons), 'vertices': sum(map(len, polygons))},
    'limits': ['Modern generalized physical coastline, not a Ming shoreline survey.',
               'Historical names are narrative labels, not borders or territorial claims.',
               'City/port area locators are not historical berths.',
               'Inland-water holes and very small islands are omitted.',
               'No relationship between longitude/latitude and local gameplay x/z metres is inferred.']}
write_json(ROOT / 'provenance.json', provenance, pretty=True)
print(json.dumps(provenance['pipeline']))
