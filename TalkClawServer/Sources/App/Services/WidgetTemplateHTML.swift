// swiftlint:disable line_length
enum WidgetTemplateHTML {

    static let clock = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
    <link rel="stylesheet" href="/static/talkclaw.css">
    </head>
    <body>
    <!-- TC:HTML -->
    <div class="tc-glass" id="root" style="display:flex;flex-direction:column;align-items:center;justify-content:center;height:100vh">
      <div class="tc-metric tc-text-accent" id="time" style="font-size:36px">--:--</div>
      <div class="tc-text-sm tc-text-secondary" id="date"></div>
    </div>
    <!-- /TC:HTML -->
    <!-- TC:STYLE -->
    <style></style>
    <!-- /TC:STYLE -->
    <!-- TC:SCRIPT -->
    <script src="/static/talkclaw-bridge.js"></script>
    <script>
    function tick() {
      var now = new Date();
      document.getElementById('time').textContent = now.toLocaleTimeString([], {hour:'2-digit',minute:'2-digit'});
      document.getElementById('date').textContent = now.toLocaleDateString([], {weekday:'long',month:'short',day:'numeric'});
    }
    tick();
    setInterval(tick, 1000);
    </script>
    <!-- /TC:SCRIPT -->
    </body>
    </html>
    """

    static let quickNotes = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
    <link rel="stylesheet" href="/static/talkclaw.css">
    </head>
    <body>
    <!-- TC:HTML -->
    <div class="tc-glass" id="root" style="height:100vh;display:flex;flex-direction:column">
      <textarea id="notes" class="tc-w-full" placeholder="Type your notes here..." style="flex:1;background:transparent;border:none;color:var(--tc-text-primary);font-family:var(--tc-font);font-size:14px;resize:none;outline:none;padding:var(--tc-space-sm)"></textarea>
    </div>
    <!-- /TC:HTML -->
    <!-- TC:STYLE -->
    <style>textarea::placeholder{color:var(--tc-text-tertiary)}</style>
    <!-- /TC:STYLE -->
    <!-- TC:SCRIPT -->
    <script src="/static/talkclaw-bridge.js"></script>
    <script>
    var ta = document.getElementById('notes');
    (async function(){
      try {
        var res = await fetch(location.pathname + '/load');
        if (res.ok) { var d = await res.json(); ta.value = d.text || ''; }
      } catch(e) {}
    })();
    var timer;
    ta.addEventListener('input', function() {
      clearTimeout(timer);
      timer = setTimeout(function() {
        fetch(location.pathname + '/save', {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({text:ta.value})});
      }, 800);
    });
    </script>
    <!-- /TC:SCRIPT -->
    <!-- TC:ROUTES
    [
      {"method":"GET","path":"/load","description":"Load saved notes","handler":"var text = (await ctx.kv.get('notes')) || ''; return {status:200,json:{text:text}};"},
      {"method":"POST","path":"/save","description":"Save notes","handler":"await ctx.kv.set('notes', req.body.text || ''); return {status:200,json:{ok:true}};"}
    ]
    -->
    </body>
    </html>
    """

    static let countdown = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
    <link rel="stylesheet" href="/static/talkclaw.css">
    </head>
    <body>
    <!-- TC:VARS
    {"target_date":"2025-12-31T00:00:00","label":"New Year"}
    -->
    <!-- TC:HTML -->
    <div class="tc-glass" id="root" style="display:flex;flex-direction:column;align-items:center;justify-content:center;height:100vh">
      <div class="tc-metric-label" id="label"></div>
      <div class="tc-flex tc-gap-md" style="margin-top:var(--tc-space-sm)">
        <div style="text-align:center"><div class="tc-metric tc-text-accent" id="days">--</div><div class="tc-text-xs tc-text-tertiary">DAYS</div></div>
        <div style="text-align:center"><div class="tc-metric tc-text-accent" id="hours">--</div><div class="tc-text-xs tc-text-tertiary">HRS</div></div>
        <div style="text-align:center"><div class="tc-metric tc-text-accent" id="mins">--</div><div class="tc-text-xs tc-text-tertiary">MIN</div></div>
      </div>
    </div>
    <!-- /TC:HTML -->
    <!-- TC:STYLE -->
    <style></style>
    <!-- /TC:STYLE -->
    <!-- TC:SCRIPT -->
    <script src="/static/talkclaw-bridge.js"></script>
    <script>
    var vars = TalkClaw.vars;
    document.getElementById('label').textContent = vars.label || 'Countdown';
    var target = new Date(vars.target_date || '2025-12-31').getTime();
    function tick() {
      var diff = Math.max(0, target - Date.now());
      var d = Math.floor(diff/86400000);
      var h = Math.floor((diff%86400000)/3600000);
      var m = Math.floor((diff%3600000)/60000);
      document.getElementById('days').textContent = d;
      document.getElementById('hours').textContent = h;
      document.getElementById('mins').textContent = m;
    }
    tick(); setInterval(tick, 60000);
    </script>
    <!-- /TC:SCRIPT -->
    </body>
    </html>
    """

    static let quoteOfTheDay = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
    <link rel="stylesheet" href="/static/talkclaw.css">
    </head>
    <body>
    <!-- TC:HTML -->
    <div class="tc-glass" id="root" style="display:flex;flex-direction:column;justify-content:center;height:100vh;padding:var(--tc-space-md)">
      <div class="tc-text-lg" id="quote" style="font-style:italic;line-height:1.6"></div>
      <div class="tc-text-sm tc-text-secondary" id="author" style="margin-top:var(--tc-space-sm);text-align:right"></div>
    </div>
    <!-- /TC:HTML -->
    <!-- TC:STYLE -->
    <style></style>
    <!-- /TC:STYLE -->
    <!-- TC:SCRIPT -->
    <script src="/static/talkclaw-bridge.js"></script>
    <script>
    var quotes = [
      {text:"The only way to do great work is to love what you do.",author:"Steve Jobs"},
      {text:"Innovation distinguishes between a leader and a follower.",author:"Steve Jobs"},
      {text:"Stay hungry, stay foolish.",author:"Stewart Brand"},
      {text:"Simplicity is the ultimate sophistication.",author:"Leonardo da Vinci"},
      {text:"The best time to plant a tree was 20 years ago. The second best time is now.",author:"Chinese Proverb"},
      {text:"Done is better than perfect.",author:"Sheryl Sandberg"},
      {text:"Move fast and break things.",author:"Mark Zuckerberg"},
      {text:"Think different.",author:"Apple"},
      {text:"If you can dream it, you can do it.",author:"Walt Disney"},
      {text:"The future belongs to those who believe in the beauty of their dreams.",author:"Eleanor Roosevelt"}
    ];
    var day = Math.floor(Date.now() / 86400000);
    var q = quotes[day % quotes.length];
    document.getElementById('quote').textContent = '\\u201c' + q.text + '\\u201d';
    document.getElementById('author').textContent = '\\u2014 ' + q.author;
    </script>
    <!-- /TC:SCRIPT -->
    </body>
    </html>
    """

    static let todoList = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
    <link rel="stylesheet" href="/static/talkclaw.css">
    </head>
    <body>
    <!-- TC:HTML -->
    <div class="tc-glass" id="root" style="height:100vh;display:flex;flex-direction:column">
      <div class="tc-flex tc-items-center tc-gap-sm" style="padding:var(--tc-space-sm)">
        <input id="input" type="text" placeholder="Add a task..." style="flex:1;background:var(--tc-surface-3);border:1px solid var(--tc-border);border-radius:var(--tc-radius-sm);padding:var(--tc-space-xs) var(--tc-space-sm);color:var(--tc-text-primary);font-family:var(--tc-font);font-size:14px;outline:none">
        <button class="tc-btn tc-btn-primary" id="add-btn" style="padding:var(--tc-space-xs) var(--tc-space-sm)">Add</button>
      </div>
      <div id="list" class="tc-scroll" style="flex:1;padding:0 var(--tc-space-sm) var(--tc-space-sm)"></div>
    </div>
    <!-- /TC:HTML -->
    <!-- TC:STYLE -->
    <style>
    .todo-item{display:flex;align-items:center;gap:var(--tc-space-sm);padding:var(--tc-space-xs) 0;border-bottom:1px solid var(--tc-border)}
    .todo-item.done .todo-text{text-decoration:line-through;opacity:0.4}
    .todo-text{flex:1;font-size:14px}
    .todo-del{background:none;border:none;color:var(--tc-text-tertiary);cursor:pointer;font-size:16px;padding:0 4px}
    input::placeholder{color:var(--tc-text-tertiary)}
    </style>
    <!-- /TC:STYLE -->
    <!-- TC:SCRIPT -->
    <script src="/static/talkclaw-bridge.js"></script>
    <script>
    var todos = [];
    function render() {
      var list = document.getElementById('list');
      list.innerHTML = todos.map(function(t,i){
        return '<div class="todo-item'+(t.done?' done':'')+'"><input type="checkbox" '+(t.done?'checked':'')+' onchange="toggle('+i+')"><span class="todo-text">'+esc(t.text)+'</span><button class="todo-del" onclick="del('+i+')">&times;</button></div>';
      }).join('');
      TalkClaw.reportHeight();
    }
    function esc(s){var d=document.createElement('div');d.textContent=s;return d.innerHTML;}
    function save(){fetch(location.pathname+'/save',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({todos:todos})});}
    window.toggle = function(i){todos[i].done=!todos[i].done;render();save();};
    window.del = function(i){todos.splice(i,1);render();save();};
    document.getElementById('add-btn').addEventListener('click',function(){
      var input=document.getElementById('input');
      var text=input.value.trim();
      if(!text)return;
      todos.push({text:text,done:false});
      input.value='';
      render();save();
    });
    document.getElementById('input').addEventListener('keydown',function(e){if(e.key==='Enter')document.getElementById('add-btn').click();});
    (async function(){
      try{var res=await fetch(location.pathname+'/load');if(res.ok){var d=await res.json();todos=d.todos||[];render();}}catch(e){}
    })();
    </script>
    <!-- /TC:SCRIPT -->
    <!-- TC:ROUTES
    [
      {"method":"GET","path":"/load","description":"Load todos","handler":"var raw = await ctx.kv.get('todos'); var todos = raw ? JSON.parse(raw) : []; return {status:200,json:{todos:todos}};"},
      {"method":"POST","path":"/save","description":"Save todos","handler":"await ctx.kv.set('todos', JSON.stringify(req.body.todos || [])); return {status:200,json:{ok:true}};"}
    ]
    -->
    </body>
    </html>
    """

    static let systemStatus = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
    <link rel="stylesheet" href="/static/talkclaw.css">
    </head>
    <body>
    <!-- TC:HTML -->
    <div class="tc-glass" id="root">
      <div class="tc-flex tc-items-center tc-justify-between" style="margin-bottom:var(--tc-space-md)">
        <span class="tc-text-sm tc-font-semibold">System Status</span>
        <span class="tc-refresh-dot" id="refresh-dot" style="display:none"></span>
      </div>
      <div class="tc-grid-2" style="gap:var(--tc-space-sm)">
        <div class="tc-card">
          <div class="tc-kv"><span class="tc-kv-label">API</span><span class="tc-status-dot tc-status-dot--ok" id="api-dot"></span></div>
        </div>
        <div class="tc-card">
          <div class="tc-kv"><span class="tc-kv-label">DB</span><span class="tc-status-dot tc-status-dot--ok" id="db-dot"></span></div>
        </div>
      </div>
      <div style="margin-top:var(--tc-space-sm)">
        <div class="tc-kv" style="margin-bottom:var(--tc-space-xs)"><span class="tc-kv-label">Uptime</span><span class="tc-kv-value" id="uptime">--</span></div>
        <div class="tc-kv" style="margin-bottom:var(--tc-space-xs)"><span class="tc-kv-label">Version</span><span class="tc-kv-value" id="version">--</span></div>
        <div class="tc-kv"><span class="tc-kv-label">Last check</span><span class="tc-kv-value" id="last-check">--</span></div>
      </div>
    </div>
    <!-- /TC:HTML -->
    <!-- TC:STYLE -->
    <style></style>
    <!-- /TC:STYLE -->
    <!-- TC:SCRIPT -->
    <script src="/static/talkclaw-bridge.js"></script>
    <script>
    function setDot(id, ok) {
      var dot = document.getElementById(id);
      dot.className = 'tc-status-dot ' + (ok ? 'tc-status-dot--ok' : 'tc-status-dot--error');
    }
    TalkClaw.startAutoRefresh(30000, async function() {
      document.getElementById('refresh-dot').style.display = '';
      try {
        var res = await fetch(location.pathname + '/check');
        if (!res.ok) throw new Error('HTTP ' + res.status);
        var d = await res.json();
        setDot('api-dot', d.apiOk);
        setDot('db-dot', d.dbOk);
        document.getElementById('uptime').textContent = d.uptime || '--';
        document.getElementById('version').textContent = d.version || '--';
        document.getElementById('last-check').textContent = new Date().toLocaleTimeString();
      } catch(e) {
        setDot('api-dot', false);
        setDot('db-dot', false);
      }
      setTimeout(function(){document.getElementById('refresh-dot').style.display='none';}, 1000);
    });
    </script>
    <!-- /TC:SCRIPT -->
    <!-- TC:ROUTES
    [
      {"method":"GET","path":"/check","description":"Check system health","handler":"try { await ctx.db.query('SELECT 1'); return {status:200,json:{apiOk:true,dbOk:true,uptime:'OK',version:'1.0'}}; } catch(e) { return {status:200,json:{apiOk:true,dbOk:false,uptime:'--',version:'--'}}; }"}
    ]
    -->
    </body>
    </html>
    """
}
// swiftlint:enable line_length
