using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Text;
using System.Threading;
using System.Windows.Forms;

static class Protocol {
    public static long Now { get { return (long)(DateTime.UtcNow-new DateTime(1970,1,1)).TotalSeconds; } }
    public static Dictionary<string,string> Read(string path) {
        var result=new Dictionary<string,string>();
        if(!File.Exists(path)) return result;
        using(var f=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete))
        using(var r=new StreamReader(f,Encoding.UTF8)) {
            string line; while((line=r.ReadLine())!=null) {
                int at=line.IndexOf('='); if(at>0) result[line.Substring(0,at)]=line.Substring(at+1);
            }
        }
        return result;
    }
    public static string Get(Dictionary<string,string> s,string key) { string v; return s.TryGetValue(key,out v)?v:""; }
    public static bool Fresh(Dictionary<string,string> s) {
        long time; return long.TryParse(Get(s,"time"),out time) && Now-time<=5 && time<=Now+2 && Get(s,"session")!="";
    }
    public static void Write(string path,string content) {
        string temp=path+".controller.tmp";
        File.WriteAllText(temp,content,new UTF8Encoding(false));
        if(File.Exists(path)) File.Replace(temp,path,null); else File.Move(temp,path);
    }
    public static string Envelope(string session) { return "session="+session+"\ntime="+Now+"\n"; }
}

sealed class TrainerWindow : Form {
    readonly string root;
    readonly System.Windows.Forms.Timer timer=new System.Windows.Forms.Timer();
    readonly Dictionary<string,CheckBox> switches=new Dictionary<string,CheckBox>();
    readonly Dictionary<string,NumericUpDown> numbers=new Dictionary<string,NumericUpDown>();
    readonly List<Button> actions=new List<Button>();
    readonly TrackBar speedSlider=new TrackBar();
    readonly Label connection=new Label(), values=new Label(), receipt=new Label(), effective=new Label();
    string session="",pending="";
    long pendingAt,lastWrite;
    bool ready,quiet;
    readonly Color ink=Color.FromArgb(35,43,39), muted=Color.FromArgb(82,95,85), green=Color.FromArgb(42,92,62);
    readonly ToolTip hints=new ToolTip();

    public TrainerWindow(string directory) {
        root=directory;Directory.CreateDirectory(root);
        Text="Kingdom Rush Frontiers · 实时修改器";
        ClientSize=new Size(590,735);MinimumSize=Size;MaximumSize=Size;
        FormBorderStyle=FormBorderStyle.FixedSingle;MaximizeBox=false;
        StartPosition=FormStartPosition.CenterScreen;
        Font=new Font("Microsoft YaHei UI",10);BackColor=Color.FromArgb(243,243,232);ForeColor=ink;
        AutoScaleMode=AutoScaleMode.Dpi;
        Label title=TextAt("前线指挥台",24,18,510,40);title.Font=new Font(Font.FontFamily,23,FontStyle.Bold);
        connection.SetBounds(26,66,540,27);connection.ForeColor=muted;Controls.Add(connection);
        values.SetBounds(26,101,540,36);values.Font=new Font(Font.FontFamily,11,FontStyle.Bold);Controls.Add(values);
        Line(146);
        TextAt("战斗资源",26,162,200,25).Font=new Font(Font,FontStyle.Bold);
        AddResource("关卡金币","gold","lock_gold",198,999999999,9999);
        AddResource("钻石 / 宝石","gems","lock_gems",245,999999999,9999);
        AddResource("剩余生命","lives","lock_lives",292,9999,99);
        TextAt("钻石写入当前存档；金币和生命只在关卡内生效。",26,341,540,26).ForeColor=muted;
        Line(379);
        TextAt("实时开关",26,392,200,25).Font=new Font(Font,FontStyle.Bold);
        AddSwitch("double_gold","双倍击杀金币",26,430,245);
        AddSwitch("power_cd","火雨 / 援军 0 CD",298,430,260);
        AddSwitch("hero_cd","英雄主动技能 0 CD",26,470,275);
        hints.SetToolTip(switches["hero_cd"],"清除英雄 timed_attacks 的冷却等待；仍需目标与施法动画。普通攻击速度不变。");
        hints.SetToolTip(switches["double_gold"],"只翻倍击杀奖励；开局金币、卖塔退款与提前召唤奖励不变。");
        var top=new CheckBox { Text="窗口置顶",AutoSize=true,Location=new Point(298,470) };
        top.CheckedChanged+=(s,e)=>TopMost=top.Checked;Controls.Add(top);
        TextAt("游戏速度",26,519,124,28);
        speedSlider.SetBounds(148,510,260,44);speedSlider.Minimum=10;speedSlider.Maximum=30;
        speedSlider.TickFrequency=5;speedSlider.SmallChange=1;speedSlider.LargeChange=5;speedSlider.Value=10;
        speedSlider.AccessibleName="游戏速度，1.0 到 3.0 倍";Controls.Add(speedSlider);
        var speed=new NumericUpDown{Location=new Point(420,514),Size=new Size(88,32),
            Minimum=1,Maximum=3,DecimalPlaces=1,Increment=0.1m,Value=1};
        numbers["speed"]=speed;Controls.Add(speed);TextAt("倍",520,519,40,28);
        speed.ValueChanged+=(s,e)=>{ speedSlider.Value=(int)(speed.Value*10);if(!quiet)TryControl(); };
        speedSlider.ValueChanged+=(s,e)=>speed.Value=speedSlider.Value/10m;
        hints.SetToolTip(speed,"每步 0.1 倍；调节后立即生效。1.0 倍为原速，菜单和声音保持正常速度。");
        effective.SetBounds(26,564,540,25);effective.ForeColor=muted;Controls.Add(effective);
        receipt.SetBounds(26,594,540,40);receipt.ForeColor=green;Controls.Add(receipt);
        var launch=ButtonAt("启动游戏",26,644,116);launch.Click+=(s,e)=>Launch();
        var off=ButtonAt("关闭全部开关",154,644,150);off.Click+=(s,e)=>AllOff();
        var read=ButtonAt("使用说明",316,644,112);read.Click+=(s,e)=>OpenFile("使用说明.md");
        var restore=ButtonAt("恢复原版",440,644,124);restore.Click+=(s,e)=>Restore();
        TextAt("关闭窗口会关闭持续开关，并将速度恢复到 1.0 倍。",26,697,540,24).ForeColor=muted;
        timer.Interval=300;timer.Tick+=(s,e)=>Tick();
        Shown+=(s,e)=>{ Tick();timer.Start(); };
        FormClosing+=(s,e)=>{ timer.Stop();try { AllOff(); } catch {} };
        connection.Text="等待游戏连接 · 首次安装后请重新启动游戏";
        values.Text="金币 —      钻石 —      生命 —";
        receipt.Text="输入目标数值后点「设置」，勾选「锁定」可持续保持。";
    }
    Label TextAt(string text,int x,int y,int w,int h) {
        var l=new Label{Text=text,AutoSize=false,Location=new Point(x,y),Size=new Size(w,h)};Controls.Add(l);return l;
    }
    void Line(int y) { Controls.Add(new Panel{Location=new Point(26,y),Size=new Size(538,1),BackColor=Color.FromArgb(190,199,181)}); }
    Button ButtonAt(string text,int x,int y,int width) {
        var b=new Button{Text=text,Location=new Point(x,y),Size=new Size(width,36),FlatStyle=FlatStyle.Flat,
            BackColor=Color.FromArgb(226,231,215),ForeColor=ink};
        b.FlatAppearance.BorderColor=Color.FromArgb(160,175,155);Controls.Add(b);return b;
    }
    void AddSwitch(string key,string text,int x,int y,int width) {
        var c=new CheckBox{Text=text,Location=new Point(x,y),Size=new Size(width,28)};
        switches[key]=c;Controls.Add(c);
        c.CheckedChanged+=(s,e)=>{if(!quiet)TryControl();};
    }
    void AddResource(string label,string key,string flag,int y,decimal max,decimal initial) {
        TextAt(label,26,y+6,124,30);
        var num=new NumericUpDown{Location=new Point(155,y),Size=new Size(194,32),Maximum=max,
            Minimum=key=="lives"?1:0,Value=initial,ThousandsSeparator=true};
        numbers[key]=num;Controls.Add(num);num.ValueChanged+=(s,e)=>{if(!quiet)TryControl();};
        var b=ButtonAt("设置",365,y-2,82);actions.Add(b);b.Enabled=false;
        b.Click+=(s,e)=>Command("set_"+key,num.Value);
        AddSwitch(flag,"锁定",470,y-1,90);
    }
    public void AllOff() {
        quiet=true;foreach(var c in switches.Values)c.Checked=false;numbers["speed"].Value=1;quiet=false;TryControl();
    }
    void TryControl() {
        if(!ready || session=="")return;
        try { WriteControl(); }
        catch(Exception ex) { receipt.Text="控制文件写入失败："+ex.Message; }
    }
    void WriteControl() {
        var b=new StringBuilder(Protocol.Envelope(session));
        foreach(var item in switches)b.Append(item.Key).Append('=').Append(item.Value.Checked?"1":"0").Append('\n');
        foreach(var item in numbers)b.Append(item.Key).Append('=').Append(item.Value.Value.ToString(item.Key=="speed"?"F1":"0",CultureInfo.InvariantCulture)).Append('\n');
        Protocol.Write(Path.Combine(root,"control.txt"),b.ToString());lastWrite=Protocol.Now;
    }
    void Command(string action,decimal value) {
        if(!ready || pending!="")return;
        string id=Guid.NewGuid().ToString("N");
        try {
            WriteControl();
            Protocol.Write(Path.Combine(root,"command.txt"),Protocol.Envelope(session)+"id="+id+"\naction="+action+"\nvalue="+value.ToString(CultureInfo.InvariantCulture)+"\n");
            pending=id;pendingAt=Protocol.Now;receipt.Text="正在等待游戏确认…";foreach(var a in actions)a.Enabled=false;
        } catch(Exception ex) { receipt.Text="发送失败："+ex.Message; }
    }
    void Tick() {
        try {
            var state=Protocol.Read(Path.Combine(root,"status.txt"));ready=Protocol.Fresh(state);
            if(!ready) {
                connection.Text="等待游戏连接 · 请启动游戏；首次安装后需重启";
                values.Text="金币 —      钻石 —      生命 —";effective.Text="持续开关未生效";
            } else {
                string incoming=Protocol.Get(state,"session");
                if(session!=incoming) { session=incoming;pending="";AllOff();receipt.Text="已连接。选择存档后可改钻石，进入关卡后可改金币。"; }
                bool battle=Protocol.Get(state,"battle")=="1";
                connection.Text=battle?"已连接 · 关卡运行中":"已连接 · 当前在菜单 / 地图";
                values.Text="金币 "+Display(state,"gold")+"     钻石 "+Display(state,"gems")+"     生命 "+Display(state,"lives")+"     存档 "+Display(state,"slot");
                int count=0;foreach(var key in switches.Keys)if(Protocol.Get(state,key)=="1")count++;
                effective.Text="游戏已确认："+count+" 个开关开启 · 战斗速度 "+Display(state,"speed")+" 倍";
                if(Protocol.Get(state,"fault")!="") { receipt.Text="游戏接口异常："+Protocol.Get(state,"fault"); }
                if(pending!="" && Protocol.Get(state,"ack")==pending) {
                    receipt.Text=ResultText(Protocol.Get(state,"result"));pending="";
                }
                if(Protocol.Now-lastWrite>=1)WriteControl();
            }
            if(pending!="" && Protocol.Now-pendingAt>6) { pending="";receipt.Text="游戏未确认本次操作，请恢复游戏运行后重试。"; }
            actions[0].Enabled=ready&&pending==""&&Protocol.Get(state,"battle")=="1";
            actions[1].Enabled=ready&&pending==""&&Protocol.Get(state,"slot")!="";
            actions[2].Enabled=actions[0].Enabled;
            foreach(var pair in switches)pair.Value.Enabled=ready;
            numbers["speed"].Enabled=ready && Protocol.Get(state,"version")=="2";
            speedSlider.Enabled=numbers["speed"].Enabled;
        } catch(IOException) { /* A brief status-file replacement gap is retried next tick. */ }
          catch(Exception ex) { receipt.Text="连接异常："+ex.Message; }
    }
    static string Display(Dictionary<string,string> s,string key) { var v=Protocol.Get(s,key);return v==""?"—":v; }
    static string ResultText(string code) {
        switch(code) {
            case "ok":return "游戏已确认：数值设置成功。";
            case "no_slot":return "尚未选择存档。请进入游戏存档后重试。";
            case "no_battle":return "当前不在关卡内。进入关卡后重试。";
            case "save_failed":return "存档保存失败；请检查存档目录权限。";
            case "bad_value":return "数值超出范围，操作未执行。";
            default:return "操作未执行："+code;
        }
    }
    void Launch() {
        try {
            if(Process.GetProcessesByName("Kingdom Rush Frontiers").Length>0) { receipt.Text="游戏已经运行。使用 Alt+Tab 切换到游戏。";return; }
            Process.Start(new ProcessStartInfo(@"D:\Steam\steamapps\common\Kingdom Rush Frontiers\Kingdom Rush Frontiers.exe") {
                WorkingDirectory=@"D:\Steam\steamapps\common\Kingdom Rush Frontiers",UseShellExecute=true});
        } catch(Exception ex) { MessageBox.Show(this,ex.Message,"启动失败"); }
    }
    void OpenFile(string name) { try { Process.Start(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,name)); }catch(Exception ex){MessageBox.Show(this,ex.Message);} }
    void Restore() {
        if(Process.GetProcessesByName("Kingdom Rush Frontiers").Length>0) { receipt.Text="请先正常退出游戏，再恢复原版。";return; }
        try {
            var psi=new ProcessStartInfo("powershell.exe","-NoProfile -ExecutionPolicy Bypass -File \""+Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"Restore-Game.ps1")+"\"") {
                UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true};
            using(var p=Process.Start(psi)) { string output=p.StandardOutput.ReadToEnd(),error=p.StandardError.ReadToEnd();p.WaitForExit();
                receipt.Text=p.ExitCode==0?"已恢复原版程序；当前存档已保留。":"恢复失败，请查看弹窗。";
                if(p.ExitCode!=0)MessageBox.Show(this,error+output,"恢复失败"); }
        } catch(Exception ex) { MessageBox.Show(this,ex.Message,"恢复失败"); }
    }
    public void SelfTest() {
        Show();Application.DoEvents();timer.Stop();
        var fake="version=2\nspeed=1.0\nsession=test\ntime="+Protocol.Now+"\nbattle=1\nslot=1\ngold=450\ngems=20\nlives=18\n";
        Protocol.Write(Path.Combine(root,"status.txt"),fake);Tick();
        if(!ready)throw new Exception("Fresh heartbeat was not connected");
        switches["double_gold"].Checked=true;numbers["gold"].Value=777;
        var c=Protocol.Read(Path.Combine(root,"control.txt"));
        if(Protocol.Get(c,"double_gold")!="1" || Protocol.Get(c,"gold")!="777")throw new Exception("Control roundtrip failed");
        for(int tenth=10;tenth<=30;tenth++) {
            speedSlider.Value=tenth;c=Protocol.Read(Path.Combine(root,"control.txt"));
            if(numbers["speed"].Value!=tenth/10m || Protocol.Get(c,"speed")!=(tenth/10m).ToString("F1",CultureInfo.InvariantCulture))
                throw new Exception("Speed slider precision or protocol failed");
        }
        numbers["speed"].Value=1.7m;
        if(speedSlider.Value!=17)throw new Exception("Speed numeric input did not sync");
        Command("set_gold",777);c=Protocol.Read(Path.Combine(root,"command.txt"));
        if(Protocol.Get(c,"action")!="set_gold" || Protocol.Get(c,"session")!="test")throw new Exception("Command roundtrip failed");
        string id=Protocol.Get(c,"id");Protocol.Write(Path.Combine(root,"status.txt"),fake+"ack="+id+"\nresult=ok\n");Tick();
        if(pending!="" || !receipt.Text.Contains("成功"))throw new Exception("Acknowledgement failed");
        AllOff();c=Protocol.Read(Path.Combine(root,"control.txt"));if(Protocol.Get(c,"double_gold")!="0" || Protocol.Get(c,"speed")!="1.0")throw new Exception("Close switches/speed reset failed");
        Protocol.Write(Path.Combine(root,"status.txt"),"session=test\ntime=1\n");Tick();
        if(ready || actions[0].Enabled)throw new Exception("Stale heartbeat accepted");
        Protocol.Write(Path.Combine(root,"status.txt"),fake.Replace("session=test","session=new"));Tick();
        if(session!="new" || switches["double_gold"].Checked)throw new Exception("Session reset failed");
        using(var bitmap=new Bitmap(Width,Height)) {
            DrawToBitmap(bitmap,new Rectangle(0,0,Width,Height));
            bitmap.Save(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"window-preview.png"));
        }
    }
}

static class Program {
    [STAThread] public static int Main(string[] args) {
        Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
        try {
            if(args.Length>0 && args[0]=="--self-test") {
                string temp=Path.Combine(Path.GetTempPath(),"FrontiersTrainerTest-"+Guid.NewGuid().ToString("N"));
                try { using(var form=new TrainerWindow(temp))form.SelfTest(); }
                finally { Directory.Delete(temp,true); }
                return 0;
            }
            bool first;using(var mutex=new Mutex(true,"Local\\CodexFrontiersTrainer",out first)) {
                if(!first)return 0;
                Application.Run(new TrainerWindow(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"ipc")));
            }
            return 0;
        }catch(Exception ex) {
            File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"controller-error.txt"),ex.ToString());
            return 1;
        }
    }
}
