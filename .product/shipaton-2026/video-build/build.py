# SameQ Shipaton demo: caption overlays via PIL, composition via ffmpeg.
import subprocess, os
from PIL import Image, ImageDraw, ImageFont
W,H=1080,1920
BG=(236,244,238); INK=(28,44,36); SUB=(90,110,98)
SRC="cfr.mp4"; ASSETS="../assets"
BGM="../../../.tmp/video-shipaton/bgm/piano.mp3"
F="/System/Library/Fonts/HelveticaNeue.ttc"
def font(sz,bold=False): return ImageFont.truetype(F,sz,index=1 if bold else 0)
def wrap(d,text,f,maxw):
    out=[]
    for para in text.split("\n"):
        cur=""
        for w in para.split():
            t=(cur+" "+w).strip()
            if d.textlength(t,font=f)<=maxw: cur=t
            else: out.append(cur); cur=w
        out.append(cur)
    return out
def caption(name,text,sub=None):
    im=Image.new("RGBA",(W,H),(0,0,0,0)); d=ImageDraw.Draw(im)
    f=font(50,True); y=1600
    for l in wrap(d,text,f,W-140):
        d.text((W/2,y),l,font=f,fill=INK,anchor="ma"); y+=64
    if sub:
        y+=14
        for l in wrap(d,sub,font(34),W-140):
            d.text((W/2,y),l,font=font(34),fill=SUB,anchor="ma"); y+=46
    im.save(name)
def card(name,title,lines):
    im=Image.new("RGB",(W,H),BG); d=ImageDraw.Draw(im)
    ic=Image.open(f"{ASSETS}/icon-1024.png").convert("RGBA").resize((300,300))
    m=Image.new("L",(300,300),0); ImageDraw.Draw(m).rounded_rectangle((0,0,299,299),68,fill=255)
    im.paste(ic,(W//2-150,440),m)
    y=820; d.text((W/2,y),title,font=font(116,True),fill=INK,anchor="ma"); y+=180
    for l,sz,col in lines:
        d.text((W/2,y),l,font=font(sz),fill=col,anchor="ma"); y+=sz+26
    im.save(name)
def still(name,png,text,sub=None):
    im=Image.new("RGB",(W,H),BG)
    s=Image.open(png).convert("RGB"); h=1480; w=round(s.width*h/s.height)
    s=s.resize((w,h)); m=Image.new("L",(w,h),0); ImageDraw.Draw(m).rounded_rectangle((0,0,w-1,h-1),48,fill=255)
    im.paste(s,((W-w)//2,70),m)
    caption("_c.png",text,sub); c=Image.open("_c.png"); im.paste(c,(0,0),c); os.remove("_c.png")
    im.save(name)

caption("c2.png","No email. No phone number.","Just an emoji and a nickname.")
caption("c3.png","Everyone in the world gets the same question today.")
caption("c4.png","You can't peek until you answer.","Then you meet one stranger's answer.")
caption("c5.png","One at a time. No followers, no feed, no ranking.","Report or block is always one tap away.")
caption("c6.png","Every answer arrives in your language.","Translated on your device. Posts never go to a translation server.")
caption("c8.png","The core experience is free. Forever.")
card("title.png","SameQ",[("One question a day,",54,INK),("for everyone in the world.",54,INK)])
card("end.png","SameQ",[("One question a day.",54,INK),("",20,INK),("Built solo for RevenueCat Shipaton 2026",38,SUB),("Available on the App Store",38,SUB)])
still("plus.png",f"{ASSETS}/05-plus.png","SameQ Plus, powered by RevenueCat.","Longer answers and text styling. 1-month free trial.\nShown in JPY here; charged in your local currency.")

VF=f"scale=-2:1480,pad={W}:{H}:(ow-iw)/2:70:color=0xECF4EE"
def run(a): subprocess.run(["ffmpeg","-v","error","-y"]+a,check=True)
def seg_video(out,ss,to,cap,speed=1.0):
    fc=(f"[0:v]trim={ss}:{to},setpts=(PTS-STARTPTS)/{speed},fps=30,{VF}[v];"
        f"[v][1:v]overlay=0:0,format=yuv420p[o]")
    run(["-i",SRC,"-i",cap,"-filter_complex",fc,"-map","[o]","-c:v","libx264","-crf","18","-r","30",out])
def seg_image(out,png,dur):
    run(["-loop","1","-t",str(dur),"-i",png,"-vf","fps=30,format=yuv420p","-c:v","libx264","-crf","18","-r","30",out])
segs=[]
def add(fn,*a):
    out=f"s{len(segs):02d}.mp4"; fn(out,*a); segs.append(out)
add(seg_image,"title.png",3.5)
add(seg_video,7.0,18.4,"c2.png",2.0)
add(seg_video,18.4,24.9,"c3.png")
add(seg_video,24.9,31.0,"c4.png")
add(seg_video,31.0,37.0,"c5.png")
add(seg_video,37.0,43.0,"c6.png")
add(seg_image,"plus.png",5.5)
add(seg_video,76.6,78.7,"c8.png")
add(seg_image,"end.png",4.5)
open("list.txt","w").write("".join(f"file '{s}'\n" for s in segs))
run(["-f","concat","-safe","0","-i","list.txt","-c","copy","video.mp4"])
dur=float(subprocess.run(["ffprobe","-v","error","-show_entries","format=duration","-of","csv=p=0","video.mp4"],capture_output=True,text=True).stdout)
# BGM: two copies crossfaded, trimmed to video length, fade in/out
fc=(f"[1:a][2:a]acrossfade=d=4[m];[m]atrim=0:{dur},afade=t=in:d=1.5,"
    f"afade=t=out:st={dur-3}:d=3,loudnorm=I=-18:TP=-2:LRA=11[a]")
run(["-i","video.mp4","-i",BGM,"-i",BGM,"-filter_complex",fc,"-map","0:v","-map","[a]",
     "-c:v","copy","-c:a","aac","-b:a","192k","-movflags","+faststart","../SameQ-Shipaton-demo.mp4"])
print(f"done {dur:.1f}s")
