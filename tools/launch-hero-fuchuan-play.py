"""Launch the ordinary game with task-owned APPDATA; no UI/state injection."""
from pathlib import Path
import os,subprocess,json,datetime,shutil
root=Path(__file__).resolve().parents[1]
out=root/'docs/production/hero-fuchuan-2026-10-25/native-play'
out.mkdir(parents=True,exist_ok=True)
stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
run_dir=out/'runs'/stamp
run_dir.mkdir(parents=True,exist_ok=False)
# Preserve earlier evidence from the original flat-log launcher.
for name in ['game.log','process.log','launch.json']:
    old=out/name
    if old.exists():shutil.copy2(old,run_dir/('previous-'+name))
profile=root/'Temp/hero-fuchuan-player-profile'
profile.mkdir(parents=True,exist_ok=True)
env=os.environ.copy();env['APPDATA']=str(profile)
exe=r'C:\Users\dains\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe'
args=['rtk','proxy',exe,'--path',str(root),'--resolution','1400x900','--position','30,30','--print-fps','--log-file',str(run_dir/'game.log')]
with (run_dir/'process.log').open('w',encoding='utf-8') as log:
    process=subprocess.Popen(args,cwd=root,env=env,stdout=log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
receipt=json.dumps({'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'pid':process.pid,'args':args,'APPDATA':str(profile),'runDirectory':str(run_dir),'scope':'Ordinary project entry; no scripted gameplay actions. Native input follows through Computer Use.'},indent=2)
(run_dir/'launch.json').write_text(receipt,encoding='utf-8')
(out/'launch.json').write_text(receipt,encoding='utf-8')
print('ORDINARY_GAME_LAUNCHED pid='+str(process.pid))
