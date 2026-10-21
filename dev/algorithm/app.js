const $ = id => document.getElementById(id);
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const money = n => '¥' + (n / 100).toFixed(2);
const roles = {hotMain:'正餐热菜',coldMain:'凉菜',side:'小吃 / 辅食',staple:'主食',soup:'汤',drink:'饮品',unknown:'角色待核对'};
const spices = ['不辣','微辣','中辣','重辣'];
const appetites = [['small','小 · 0.5'],['normal','正常 · 1'],['large','大 · 1.5'],['extraLarge','特别大 · 2']];
const units = {small:1,normal:2,large:3,extraLarge:4};
const split = s => [...new Set(String(s).split(/[,，、;；\n]/).map(x => x.trim()).filter(Boolean))];
let menu, members=[], seq=0, result=null, lastInput=null, dirty=true, busy=false;
let unknown=new Set(), unavailable=new Set();
const meta = id => menu?.mealMetadata.find(m => m.dishId===id) || {role:'unknown',stapleUnits:null,primaryIngredients:[]};
const defaultFields=['appetite','maxSpiceLevel','allergens','avoidFoods','tastePreferences'];
const memberName = index => index===0?'发起人':`同行人 ${String.fromCharCode(64+index)}`;
const member = (name='成员',autoName=true) => ({id:'m'+(++seq),nickname:name,autoName,submitted:true,allergens:'',avoidFoods:'',maxSpiceLevel:'',tastePreferences:'',wishes:[],appetite:'normal',stapleMode:'default',stapleDishId:'',wantedIngredients:[],wantedExtras:{},wantedSpiceLevel:'',note:'',pending:null});
function normalizeMemberNames(){members.forEach((m,index)=>{if(m.autoName)m.nickname=memberName(index);});}
function syncMembersToPeople(){
 const people=Number($('people').value);
 if(!Number.isInteger(people)||people<1||people>12)return false;
 while(members.length<people)members.push(member(memberName(members.length)));
 if(members.length>people)members=members.slice(0,people);
 normalizeMemberNames();return true;
}
function status(text,error=false){$('status').className='banner'+(error?' error':'');$('status').textContent=text;}
function demandPreview(){
 const active=members.filter(m=>m.submitted), n=Number($('people').value)||0;
 const u=active.reduce((s,m)=>s+units[m.appetite],0)+Math.max(0,n-active.length)*2;
 const staple=Math.max(0,n-active.filter(m=>m.stapleMode==='none').length);
 $('demand-preview').textContent=`当前估算：${Math.ceil(u/2)} 份热菜 · ${staple} 个主食单位。${n>active.length?`${n-active.length} 位未提交者按正常饭量预留，要求待补充。`:''}`;
}
function invalidate(){dirty=true;$('export').disabled=true;document.querySelector('.results').style.opacity=result?'.55':'1';if(result)status('参数已修改，请重新运行当前菜单版本。旧方案仅作参考。');demandPreview();renderMenu();}
function optionList(values,current){return values.map(([v,t])=>`<option value="${esc(v)}" ${String(current)===v?'selected':''}>${esc(t)}</option>`).join('');}
function extraSummary(m){const values=Object.values(m.wantedExtras).filter(n=>n>0);return `${values.length} 种 / ${values.reduce((a,b)=>a+b,0)} 份`;}
function importExtras(o){
 const result={},seenNew=new Set(),valid=id=>menu.dishes.some(d=>d.id===id&&['side','drink'].includes(meta(d.id).role));
 for(const id of o.wantedExtraIds||[])if(valid(id))result[id]=(result[id]||0)+1;
 if(o.wantedExtras!==undefined&&!Array.isArray(o.wantedExtras))throw Error('额外小吃 / 饮料字段无效。');
 for(const wish of o.wantedExtras||[]){
  if(!wish||typeof wish.dishId!=='string'||!valid(wish.dishId)||!Number.isInteger(wish.quantity)||wish.quantity<1||wish.quantity>100||seenNew.has(wish.dishId))throw Error('额外小吃 / 饮料份数无效。');
  seenNew.add(wish.dishId);
  result[wish.dishId]=wish.quantity;
 }
 return result;
}
function renderMembers(){
 $('members').innerHTML=members.map(m=>`<div class="member ${m.submitted?'':'off'}" data-member="${esc(m.id)}">
 <div class="member-head"><input type="text" data-field="nickname" aria-label="姓名" value="${esc(m.nickname)}" maxlength="30"><label><input type="checkbox" data-field="submitted" ${m.submitted?'checked':''}> 已提交</label><button type="button" class="remove" data-remove="${esc(m.id)}" aria-label="删除成员">×</button></div>
 <div class="row"><label>过敏食物<input data-field="allergens" list="allergen-options" value="${esc(m.allergens)}" placeholder="大豆、花生、鸡蛋、小麦"></label><label>明确不吃<input data-field="avoidFoods" list="avoid-options" value="${esc(m.avoidFoods)}" placeholder="香菜、葱、猪肉、内脏"></label></div>
 <div class="row"><label>最高辣度<select data-field="maxSpiceLevel">${optionList([['','都可以'],...spices.map((s,i)=>[String(i),s])],m.maxSpiceLevel)}</select></label><label>饭量<select data-field="appetite">${optionList(appetites,m.appetite)}</select></label></div>
 <label>想吃的辣度（软愿望）<select data-field="wantedSpiceLevel">${optionList([['','没有指定'],...spices.map((s,i)=>[String(i),s])],m.wantedSpiceLevel)}</select></label>
 <label>口味偏好<input data-field="tastePreferences" list="taste-options" value="${esc(m.tastePreferences)}" placeholder="清淡、酸甜、咸香（逗号分隔）"></label>
 <details><summary>想吃的食材 · 已选 ${m.wantedIngredients.length} 项</summary><input type="search" data-ingredient-search="${esc(m.id)}" placeholder="搜索本店食材"><div class="chips">${menu.ingredientOptions.map(i=>`<label data-term="${esc(i)}"><input type="checkbox" data-ingredient="${esc(i)}" ${m.wantedIngredients.includes(i)?'checked':''}>${esc(i)}</label>`).join('')}</div><p class="hint">隐藏水等低信息选项只影响展示，不修改配方和过敏校验。主料未核对时不冒认愿望已满足。</p></details>
 <details><summary>指定菜品 · 已选 ${m.wishes.length} 项</summary><select data-field="wishes" aria-label="指定想吃的菜" multiple size="4">${menu.dishes.filter(d=>!['side','drink'].includes(meta(d.id).role)).map(d=>`<option value="${esc(d.id)}" ${m.wishes.includes(d.id)?'selected':''}>${esc(d.name)} · ${money(d.priceFen)}</option>`).join('')}</select></details>
 <details><summary>额外小吃 / 饮料 · ${extraSummary(m)}</summary><div class="extra-grid">${menu.dishes.filter(d=>['side','drink'].includes(meta(d.id).role)).map(d=>`<label>${esc(d.name)} · ${money(d.priceFen)}<input type="number" min="0" max="100" step="1" inputmode="numeric" data-extra-id="${esc(d.id)}" aria-label="${esc(d.name)}份数" value="${m.wantedExtras[d.id]||0}"></label>`).join('')}</div><p class="hint">每种可选 0–100 份；明确数量按原数处理。设置预算时，算法也可自动加入适配项以接近目标档位；均不抵热菜或主食数量。</p></details>
 <label>本次主食<select data-field="stapleMode">${optionList([['default','默认：一份普通米饭'],['none','明确不要主食'],['noodles','换面条'],['specified','指定其他主食']],m.stapleMode)}</select></label>
 ${['noodles','specified'].includes(m.stapleMode)?`<label>选择具体主食<select data-field="stapleDishId"><option value="">${m.stapleMode==='noodles'?'自动选择已核对的单人份面条':'请选择'}</option>${menu.dishes.filter(d=>meta(d.id).role==='staple'&&meta(d.id).stapleUnits===1&&(m.stapleMode!=='noodles'||meta(d.id).stapleKind==='noodles')).map(d=>`<option value="${esc(d.id)}" ${m.stapleDishId===d.id?'selected':''}>${esc(d.name)} · ${money(d.priceFen)}</option>`).join('')}</select></label><p class="hint">这里只显示菜单事实中已核对为一个单人单位的主食；仍会校验过敏和其他限制。</p>`:''}
 <label>其他要求（需核对解释）<textarea data-field="note" rows="2" maxlength="200" placeholder="例如：不想吃米饭，改吃面条">${esc(m.note)}</textarea></label><button type="button" data-parse-note="${esc(m.id)}">提议结构化解释</button>
 ${m.pending?`<div class="note-preview">${esc(m.pending.text)}${m.pending.patch?` <button type="button" data-apply-note="${esc(m.id)}">确认应用</button>`:''}</div>`:''}
 </div>`).join('');
 const selected=$('member-filter').value;
 $('member-filter').innerHTML='<option value="">查看整桌</option>'+members.filter(m=>m.submitted).map(m=>`<option value="${esc(m.id)}">${esc(m.nickname)}</option>`).join('');
 $('member-filter').value=selected;demandPreview();
}
function preferences(m){return {allergens:split(m.allergens),avoidFoods:split(m.avoidFoods).map(s=>s.replace(/^(不吃|不要|忌口[:：]?)/,'')),dietMode:'none',maxSpiceLevel:m.maxSpiceLevel===''?null:Number(m.maxSpiceLevel),tastePreferences:split(m.tastePreferences),wantedDishIds:m.wishes,wantedSetMealIds:[],note:m.note};}
function input(){
 const people=Number($('people').value), text=$('budget').value.trim();
 if(!Number.isInteger(people)||people<1||people>12||members.length>people)throw Error('人数须为 1–12，且不能小于已有成员数。');
 if(!members.some(m=>m.submitted))throw Error('请至少提交一位成员的需求。');
 if(text&&!/^\d+(\.\d{1,2})?$/.test(text))throw Error('预算须为非负金额，最多两位小数。');
 const [whole,fraction='']=text.split('.'),budget=text?Number(whole)*100+Number(fraction.padEnd(2,'0')):null;
 if(budget!==null&&(!Number.isSafeInteger(budget)||budget>10000000))throw Error('人均预算最多 100000 元。');
 if(members.some(m=>m.stapleMode==='specified'&&!m.stapleDishId))throw Error('请选择指定主食，或切回默认米饭。');
 if(members.some(m=>Object.values(m.wantedExtras).some(n=>!Number.isInteger(n)||n<1||n>100)))throw Error('每种小吃或饮料须选择 1–100 份。');
 const algorithm=$('algorithm').value;
 return {algorithm,menuVersion:menu.menuVersion,people,budgetPerPersonFen:budget,maxExpansions:algorithm==='v1'?Math.min(5000,Number($('expansions').value)):Number($('expansions').value),width:Number($('width').value),unknownDishIds:[...unknown],unavailableDishIds:[...unavailable],members:members.map(m=>({id:m.id,nickname:m.nickname,submitted:m.submitted,preferences:preferences(m),meal:{appetite:m.appetite,stapleMode:m.stapleMode,stapleDishId:m.stapleDishId||null,wantedIngredients:m.wantedIngredients,wantedExtras:Object.entries(m.wantedExtras).map(([dishId,quantity])=>({dishId,quantity})),wantedSpiceLevel:m.wantedSpiceLevel===''?null:Number(m.wantedSpiceLevel)}}))};
}
function cover(draft,id){return new Set(draft.fits.filter(f=>f.memberId===id&&draft.expandedDishes.some(x=>x.dish.id===f.dishId&&meta(x.dish.id).role==='hotMain')).map(f=>f.dishId)).size;}
function wishName(w){return w.itemType==='ingredient'?`食材：${w.itemId}`:w.itemType==='spice'?`辣度：${spices[Number(w.itemId.split('-')[1])]}`:menu.dishes.find(d=>d.id===w.itemId)?.name||w.itemId;}
function renderResult(id,draft){
 const active=lastInput.members.filter(m=>m.submitted), report=id==='optimized'?result.mealReport:null;
 const zero=active.filter(m=>cover(draft,m.id)===0).length,low=active.filter(m=>cover(draft,m.id)===1).length;
 $(id).innerHTML=`<div class="metric money">${money(draft.totalFen)} <span>整桌 · 人均 ${money(Math.round(draft.totalFen/lastInput.people))}</span></div>
 ${report?`<div class="report-box ${report.status==='complete'?'':'warn'}"><b>${{complete:'估算需求完整',partial:'有明确需求缺口',noCandidate:'预算内没有可用方案'}[report.status]}</b><br>热菜 ${report.estimatedHotSupply} / ${report.estimatedHotNeed} 份 · ${report.targetBandReached?'达到90%–100%预算档位':'未达到预算档位'}<br>${report.deficits.map(esc).join('<br>')}</div>`:'<p class="hint">原算法对照：没有 v3 的饭量、动态食材愿望和主食覆盖能力。</p>'}
 <div class="statline"><span class="tag ${zero?'red':''}">无正餐热菜 ${zero} 人</span><span class="tag ${low?'warn':''}">仅1种热菜 ${low} 人</span><span class="tag neutral">未满足愿望 ${draft.unmetWishes.length}</span></div>
 ${active.map(m=>{const n=cover(draft,m.id),a=report?.members.find(x=>x.memberId===m.id),staple=a?.stapleDishId?menu.dishes.find(d=>d.id===a.stapleDishId)?.name:a?.stapleOptOut?'明确不要主食':'主食缺口';return `<div class="person-result"><div>${esc(m.nickname)}${a?`<div class="allocation">估算分配 ${a.halfDishAllocated/2} / ${a.halfDishNeed/2} 道 · ${esc(staple)}</div>`:''}</div><span class="tag ${n===0?'red':n===1?'warn':''}">${n} 种适配热菜</span></div>`;}).join('')}
 ${draft.items.map(i=>{const d=i.itemType==='setMeal'?menu.setMeals?.find(d=>d.id===i.itemId):menu.dishes.find(d=>d.id===i.itemId),description=d?.description?.trim();return `<div class="dish-row">${d?.imageUrl?`<img loading="lazy" src="${esc(d.imageUrl)}" alt="">`:'<div></div>'}<div>${esc(i.name)}<small>${i.itemType==='setMeal'?'固定套餐':esc(roles[meta(i.itemId).role])} · ${money(i.unitPriceFen)} / 份</small>${description?`<small class="dish-description">${esc(description)}</small>`:''}</div><span class="money">×${i.quantity}<br>${money(i.quantity*i.unitPriceFen)}</span></div>`;}).join('')||'<p class="hint">暂无可用条目，请核对需求或预算。</p>'}
 ${draft.budgetWarning?`<div class="notice">${esc(draft.budgetWarning)}</div>`:''}
 <details><summary>未满足愿望与解释</summary>${draft.unmetWishes.map(w=>`<p class="hint">${esc(lastInput.members.find(m=>m.id===w.memberId)?.nickname)} / ${esc(wishName(w))}：${esc(w.reason)}</p>`).join('')||'<p class="hint">没有未满足的已识别愿望。</p>'}</details>
 <details><summary>事实提示与估算边界</summary><p class="hint">${draft.notices.map(esc).join('<br>')}</p></details>`;
}
function renderMenu(){
 if(!menu)return;
 const term=$('filter').value.toLowerCase(),mid=$('member-filter').value,filter=$('fit-filter').value;let count=0;const rows=[];
 for(const d of menu.dishes){
  if(!(d.name+' '+d.ingredients.join(' ')).toLowerCase().includes(term))continue;
  const row=!dirty&&result?result.eligibility.find(r=>r.dishId===d.id):null, fit=row?.fits.find(f=>f.memberId===mid);
  if(filter==='excluded'&&!row?.tableExcluded)continue;
  if(['fit','conflict','uncertain'].includes(filter)&&fit?.status!==filter)continue;
  count++;let reason='<span class="subtitle">运行后查看</span>';
  if(row){reason=row.tableExcluded?'<span class="tag red">整桌规则排除 / 不可售</span>':'<span class="tag">未被整桌排除</span>';if(fit)reason+=` <span class="tag ${fit.status==='fit'?'':fit.status==='conflict'?'red':'warn'}">${{fit:'本人适配',conflict:'本人冲突',uncertain:'本人不确定'}[fit.status]}</span><p class="subtitle">${fit.reasons.map(esc).join('；')}</p>`;else if(!mid)reason+=`<p class="subtitle">${row.fits.filter(f=>f.status==='fit').length} / ${row.fits.length} 位已提交者适配</p>`;}
  rows.push(`<tr><td class="name">${esc(d.name)}<br><span class="money subtitle">${money(d.priceFen)}</span></td><td>${esc(roles[meta(d.id).role])}<br><span class="subtitle">${spices[d.spiceLevel]}</span></td><td class="recipe">${esc(d.ingredients.join('、'))}${unknown.has(d.id)?'<span class="tag warn">+ unknown（模拟）</span>':''}</td><td class="reason">${reason}</td><td class="sim"><label><input type="checkbox" data-sim="unknown" data-id="${esc(d.id)}" ${busy?'disabled':''} ${unknown.has(d.id)?'checked':''}>食材不详</label><label><input type="checkbox" data-sim="unavailable" data-id="${esc(d.id)}" ${busy?'disabled':''} ${unavailable.has(d.id)?'checked':''}>下架</label></td></tr>`);
 }
 $('menu-body').innerHTML=rows.join('');$('menu-meta').textContent=`共 ${menu.dishes.length} 道 · 显示 ${count} 道 · 模拟 unknown ${unknown.size} / 下架 ${unavailable.size}`;
}
function loadDefaults(m){try{const d=JSON.parse(localStorage.getItem('huaiwei-meal-defaults-v3')||'null');if(d&&units[d.appetite])for(const key of defaultFields)if(typeof d[key]==='string')m[key]=d[key];}catch{status('本地默认值不可用，本次使用空白要求。',true);}}
function preset(kind){
 const count=kind==='five'?5:4;
 members=Array.from({length:count},(_,index)=>member(memberName(index)));
 if(kind==='normal')loadDefaults(members[0]);
 $('people').value=members.length;$('budget').value=kind==='budget'?'3':kind==='five'?'45':'25';unknown.clear();unavailable.clear();
 if(kind==='allergy'||kind==='five')members[0].allergens='花生';
 if(kind==='five'){members[1].maxSpiceLevel='0';members[2].avoidFoods='猪肉';members[3].wantedSpiceLevel='3';}
 if(kind==='wish'){members[0].maxSpiceLevel='0';const d=menu.dishes.find(d=>d.name==='香辣鸡杂');if(d)members[0].wishes=[d.id];}
 renderMembers();invalidate();
}
async function run(){
 if(busy||!menu)return;let body;try{body=input();}catch(e){status(e.message,true);return;}
 busy=true;$('controls').disabled=true;$('reset-sim').disabled=true;$('import').disabled=true;renderMenu();status('正在执行真实仓颉算法，核对饭量、主食、个人适配和预算…');
 try{
  const response=await fetch('/api/dev/recommend',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(20000)});
  const data=await response.json();if(!response.ok)throw Error(data.error?.message||'推荐失败');
  result=data;lastInput=body;dirty=false;document.querySelector('.results').style.opacity='1';$('search-title').textContent=data.algorithm==='v3'?'B2 选择器 v3':'保留实验 v1';
  renderResult('baseline',data.baseline);renderResult('optimized',data.optimized);$('export').disabled=false;
  const report=data.mealReport;
  status(`${report?`v3 ${report.status==='complete'?'已满足当前估算需求':'存在需求缺口'}，${report.targetBandReached?'达到目标预算档位':'未达到目标预算档位'}。`:'v1 对照运行完成。'}扩展 ${data.expansions} 次 · ${data.elapsedMillis} ms · 菜单 v${data.menuVersion}${data.stoppedByDeadline?' · 到达时限':data.stoppedByLimit?' · 到达扩展上限':''}。${body.members.filter(m=>m.submitted).length<body.people?'未提交者的要求仍待补充。':''}`);
 }catch(e){dirty=true;$('export').disabled=true;status(e.name==='TimeoutError'?'请求超时，请降低搜索规模。':e.message,true);}
 finally{busy=false;$('controls').disabled=false;$('reset-sim').disabled=false;$('import').disabled=false;renderMenu();}
}
$('members').addEventListener('input',e=>{
 const el=e.target;
 if(el.dataset.ingredientSearch){const term=el.value.toLowerCase();el.closest('details').querySelectorAll('[data-term]').forEach(x=>x.hidden=!x.dataset.term.toLowerCase().includes(term));}
});
$('members').addEventListener('change',e=>{
 const el=e.target,root=el.closest('[data-member]');if(!root)return;const m=members.find(m=>m.id===root.dataset.member);
 if(el.dataset.ingredient){const set=new Set(m.wantedIngredients);el.checked?set.add(el.dataset.ingredient):set.delete(el.dataset.ingredient);m.wantedIngredients=[...set];el.closest('details').querySelector('summary').textContent=`想吃的食材 · 已选 ${set.size} 项`;invalidate();return;}
 if(el.dataset.extraId){const quantity=Number(el.value);if(Number.isInteger(quantity)&&quantity>0)m.wantedExtras[el.dataset.extraId]=quantity;else delete m.wantedExtras[el.dataset.extraId];el.closest('details').querySelector('summary').textContent=`额外小吃 / 饮料 · ${extraSummary(m)}`;invalidate();return;}
 const field=el.dataset.field;if(!field)return;
 m[field]=el.type==='checkbox'?el.checked:field==='wishes'?[...el.selectedOptions].map(x=>x.value):el.value;
 if(field==='nickname')m.autoName=false;
 if(field==='note')m.pending=null;
 if(field==='stapleMode')m.stapleDishId='';
 if(['submitted','stapleMode','stapleDishId'].includes(field))renderMembers();
 if(field==='wishes')el.closest('details').querySelector('summary').textContent=`指定菜品 · 已选 ${m[field].length} 项`;
 invalidate();
});
$('members').addEventListener('click',e=>{
 const id=e.target.dataset.remove;
 if(id){if(members.length===1){status('至少保留一位成员。',true);return;}members=members.filter(m=>m.id!==id);$('people').value=members.length;normalizeMemberNames();renderMembers();invalidate();return;}
 const parse=e.target.dataset.parseNote, apply=e.target.dataset.applyNote;
 if(parse){const m=members.find(m=>m.id===parse),t=m.note.trim();let patch=null,text='没有识别出可自动提议的主食要求，请直接修改主食选项。';
  if(/(不要|不吃|不想吃)主食/.test(t)){patch={stapleMode:'none',stapleDishId:''};text='提议：此成员本次不要主食，其他人的主食保持不变。';}
  else if(/(面条|吃面|换面)/.test(t)){patch={stapleMode:'noodles',stapleDishId:''};text='提议：此成员本次米饭换成菜单中已核对为单人份的面条。';}
  else if(/(不想吃饭|不吃饭|不吃米饭|不要米饭)/.test(t))text='这句话可能表示不要主食或换其他主食，请本人明确选择；尚未更改主食。';
  m.pending={patch,text};renderMembers();
 }
 if(apply){const m=members.find(m=>m.id===apply);if(m.pending?.patch)Object.assign(m,m.pending.patch);m.pending=null;renderMembers();invalidate();}
});
$('presets').addEventListener('click',e=>{if(menu&&e.target.dataset.preset)preset(e.target.dataset.preset);});
$('add').onclick=()=>{if(members.length>=12){status('本地调试最多 12 位成员。',true);return;}members.push(member(memberName(members.length)));$('people').value=members.length;renderMembers();invalidate();};
$('people').addEventListener('change',()=>{if(syncMembersToPeople())renderMembers();invalidate();});
for(const id of ['budget','expansions','width','algorithm'])$(id).addEventListener('change',invalidate);
for(const id of ['filter','member-filter','fit-filter'])$(id).addEventListener(id==='filter'?'input':'change',renderMenu);
$('menu-body').addEventListener('change',e=>{const {sim,id}=e.target.dataset;if(!sim)return;const set=sim==='unknown'?unknown:unavailable;e.target.checked?set.add(id):set.delete(id);invalidate();});
$('reset-sim').onclick=()=>{unknown.clear();unavailable.clear();invalidate();};$('run').onclick=run;
$('save-defaults').onclick=()=>{try{const d=Object.fromEntries(defaultFields.map(k=>[k,members[0][k]]));localStorage.setItem('huaiwei-meal-defaults-v3',JSON.stringify(d));status('第1位成员的常用要求已保存到此浏览器，未保存本局愿望、主食覆盖或文字，未调用账号 API。');}catch{status('浏览器不允许保存本地默认值。',true);}};
$('export').onclick=()=>{if(dirty||!result)return;const blob=new Blob([JSON.stringify({format:'huaiwei-algorithm-experiment-v3',input:lastInput,result},null,2)],{type:'application/json'}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download='laoxiangji-v3-experiment.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);};
$('import').onclick=()=>$('file').click();
$('file').onchange=async()=>{
 try{const f=$('file').files[0];if(!f)return;if(f.size>4*1024*1024)throw Error('文件不能超过 4 MB。');const data=JSON.parse(await f.text()),i=data.input;
  if(!['huaiwei-algorithm-experiment-v1','huaiwei-algorithm-experiment-v3'].includes(data.format)||!Array.isArray(i?.members)||i.members.length<1||i.members.length>12)throw Error('文件格式无效。');
  if(i.members.some(m=>typeof m.id!=='string'||!m.id||m.id.length>128)||new Set(i.members.map(m=>m.id)).size!==i.members.length)throw Error('成员 ID 无效。');
  members=i.members.map(row=>{const p=row.preferences;if(!p||!['allergens','avoidFoods','tastePreferences','wantedDishIds'].every(k=>Array.isArray(p[k])))throw Error('成员字段无效。');const m=member(String(row.nickname||'成员'),false),o=row.meal||{};return {...m,id:row.id,submitted:!!row.submitted,allergens:p.allergens.join('、'),avoidFoods:p.avoidFoods.join('、'),maxSpiceLevel:p.maxSpiceLevel===null?'':String(p.maxSpiceLevel),tastePreferences:p.tastePreferences.join('、'),wishes:p.wantedDishIds.filter(id=>menu.dishes.some(d=>d.id===id)),note:String(p.note||''),appetite:units[o.appetite]?o.appetite:'normal',stapleMode:['default','none','noodles','specified'].includes(o.stapleMode)?o.stapleMode:'default',stapleDishId:menu.dishes.some(d=>d.id===o.stapleDishId&&meta(d.id).role==='staple'&&meta(d.id).stapleUnits===1)?o.stapleDishId:'',wantedIngredients:(o.wantedIngredients||[]).filter(x=>menu.ingredientOptions.includes(x)),wantedExtras:importExtras(o),wantedSpiceLevel:o.wantedSpiceLevel==null?'':String(o.wantedSpiceLevel)};});
  seq=Math.max(seq,...members.map(m=>/^m\d+$/.test(m.id)?Number(m.id.slice(1)):0));$('people').value=i.people;$('budget').value=i.budgetPerPersonFen==null?'':(i.budgetPerPersonFen/100).toFixed(2);$('algorithm').value=i.algorithm==='v1'?'v1':'v3';
  $('expansions').value=['480','3000','6000','12000'].includes(String(i.maxExpansions))?String(i.maxExpansions):'6000';$('width').value=['6','16','32'].includes(String(i.width))?String(i.width):'16';
  unknown=new Set((i.unknownDishIds||[]).filter(id=>menu.dishes.some(d=>d.id===id)));unavailable=new Set((i.unavailableDishIds||[]).filter(id=>menu.dishes.some(d=>d.id===id)));renderMembers();invalidate();status('已载入实验输入。请按当前菜单重跑，旧结果未作为事实使用。');
 }catch(e){status('载入失败：'+e.message,true);}finally{$('file').value='';}
};
try{const r=await fetch('/api/dev/menu'),data=await r.json();if(!r.ok)throw Error(data.error?.message||'菜单加载失败');menu=data;$('controls').disabled=false;$('source').textContent=`${menu.restaurant.name} · ${menu.dishes.length} 道菜 · v${menu.menuVersion} · B2 v3`;preset('normal');status('v3 已就绪：可选择饭量、主食、动态愿望，或直接试「5人 / 45元 / 重辣」。');}catch(e){status('菜单加载失败：'+e.message,true);$('controls').disabled=true;}
