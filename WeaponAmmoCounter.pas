unit WeaponAmmoCounter;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

{$define DISABLE_AUTOAMMOCHANGE}  //îòêëþ÷àåò àâòîìàòè÷åñêóþ ñìåíó òèïà ïàòðîíîâ ïî íàæàòèþ êëàâèøè ðåëîàäà ïðè îòñóòñâèè ïàòðîíîâ òåêóùåãî òèïà; ïðè àíäåôå ïîëîìàþòñÿ äâóñòâîëû, êîãäà â èíâåíòàðå ïîñëåäíèé ïàòðîí!

interface
  procedure CWeaponMagazined__OnAnimationEnd_DoReload(wpn:pointer); stdcall;
  function CWeaponShotgun__OnAnimationEnd_OnAddCartridge(wpn:pointer):boolean; stdcall;  

function Init:boolean;

implementation
uses BaseGameData, WeaponAdditionalBuffer, HudItemUtils, xr_Cartridge, ActorUtils, strutils, ActorDOF, gunsl_config, sysutils, dynamic_caster, xr_strings;


procedure SwapFirstLastAmmo(wpn:pointer);stdcall;
var
  cs, ce:pCCartridge;
  tmp:CCartridge;
  cnt, gl_status:cardinal;
begin
  gl_status:=GetGLStatus(wpn);
  if ((gl_status=1) or ((gl_status=2) and IsGLAttached(wpn))) and IsGLEnabled(wpn) then exit;
  cnt:=GetAmmoInMagCount(wpn);
  if cnt>1 then begin
    cnt:=cnt-1;
    cs:=GetCartridgeFromMagVector(wpn,0);
    ce:=GetCartridgeFromMagVector(wpn,cnt);
    CopyCartridge(cs^, tmp);
    CopyCartridge(ce^, cs^);
    CopyCartridge(tmp, ce^);
  end;
end;

procedure SwapLastPrevAmmo(wpn:pointer);stdcall;
var
  cs, ce:pCCartridge;
  tmp:CCartridge;
  cnt, gl_status:cardinal;
begin
  gl_status:=GetGLStatus(wpn);
  if ((gl_status=1) or ((gl_status=2) and IsGLAttached(wpn))) and IsGLEnabled(wpn) then exit;
  cnt:=GetAmmoInMagCount(wpn);
  if cnt>1 then begin
    cnt:=cnt-1;
    cs:=GetCartridgeFromMagVector(wpn,cnt-1);
    ce:=GetCartridgeFromMagVector(wpn,cnt);
    CopyCartridge(cs^, tmp);
    CopyCartridge(ce^, cs^);
    CopyCartridge(tmp, ce^);
  end;
end;


//---------------------------------------------------Ñâîå ÷èñëî ïàòðîíîâ â ðåëîàäå-------------------------
procedure CWeaponMagazined__OnAnimationEnd_DoReload(wpn:pointer); stdcall;
var
  buf: WpnBuf;
  def_magsize, mod_magsize, curammocnt:integer;
  gl_status:cardinal;
begin
  buf:=GetBuffer(wpn);
  //åñëè áóôåðà íåò èëè ìû óæå ïåðåçàðÿäèëècü èëè ó íàñ ðåæèì ïîäñòâîëà - íè÷åãî îñîáåííîãî íå äåëàåì
  if (buf=nil) then begin virtual_CWeaponMagazined__ReloadMagazine(wpn); exit; end;

  if buf.IsReloaded() then begin buf.SetReloaded(false); exit; end;
  gl_status:=GetGLStatus(wpn);
  if (((gl_status=1) or ((gl_status=2) and IsGLAttached(wpn))) and IsGLEnabled(wpn)) then begin virtual_CWeaponMagazined__ReloadMagazine(wpn); exit; end;

  //ïîñìîòðèì, êàêîâ ðàçìåð ìàãàçèíà ó îðóæèÿ è ñêîëüêî ïàòðîíîâ â íåì ñåé÷àñ
  def_magsize:=GetMagCapacityInCurrentWeaponMode(wpn);
  curammocnt:=GetCurrentAmmoCount(wpn);

  //òåïåðü ïîñìîòðèì íà ñîñòîÿíèå îðóæèÿ è ïîäóìàåì, ñêîëüêî ïàòðîíîâ â íåãî çàïèõíóòü
  if IsWeaponJammed(wpn) then begin
    SetAmmoTypeChangingStatus(wpn, $FF);
    mod_magsize:=curammocnt-1;
  end else if IsBM16(wpn) then begin
    mod_magsize:=buf.ammo_cnt_to_reload;
  end else if not IsGrenadeMode(wpn) and buf.IsAmmoInChamber() and ((curammocnt=0) or ((GetAmmoTypeChangingStatus(wpn)<>$FF) and not buf.SaveAmmoInChamber() )) then begin
    mod_magsize:=def_magsize-1;
  end else begin
    mod_magsize:=def_magsize;
  end;

  //èçìåíèì åìêîñòü ìàãàçèíà, îòðåëîàäèìñÿ äî íåå è âîññòàíîâèì ñòàðîå çíà÷åíèå
  SetMagCapacityInCurrentWeaponMode(wpn, mod_magsize);
  virtual_CWeaponMagazined__ReloadMagazine(wpn);
  SetMagCapacityInCurrentWeaponMode(wpn, def_magsize);
end;


procedure CWeaponMagazined__OnAnimationEnd_DoReload_Patch(); stdcall;
asm
  pushad
    sub esi, $2e0
    push esi
    call CWeaponMagazined__OnAnimationEnd_DoReload
  popad
end;


//---------------------------------------------------Íåñìåíà òèïà ïàòðîíà â ïàòðîííèêå â ðåëîàäå-------------------------
procedure PerformUnloadAmmo(wpn:pointer); stdcall;
var
  buf:WpnBuf;
  need_unload:boolean;
  i, cnt:integer;
begin
  buf:=GetBuffer(wpn);
  //Âûçûâàåòñÿ ïðè ÊÀÆÄÎÉ ïåðåçàðÿäêå ïðè ÍÅÏÓÑÒÎÌ ìàãàçèíå - íå òîëüêî ïðè ñìåíå òèïà ïàòðîíîâ (ýòî ïðîïàò÷åíî äðóãîé âðåçêîé)

  if buf <> nil then begin
    buf.is_firstlast_ammo_swapped:=false;

    if not IsGrenadeMode(wpn) and buf.IsAmmoInChamber() and buf.SaveAmmoInChamber() then begin
      //Ïðè èñïîëüçîâàíèè ñõåìû ñ ïàòðîííèêîì â ïàòðîíå íå ðàçðÿæàåì ïàòðîí â ïàòðîííèêå

      //Ìåíÿåì ìåñòàìè ïåðâûé ïàòðîí èç âåêòîðà ìàãàçèíà ñ ïîñëåäíèì
      //Ïîñëå ýòîãî íà ìåñòå ïåðâîãî ïàòðîíà îêàçûâàåòñÿ ïàòðîí èç ïàòðîííèêà
      SwapFirstLastAmmo(wpn);
      buf.is_firstlast_ammo_swapped:=true;

      // Õàê - ñìåùàåì óêàçàòåëü íà ïåðâûé ýëåìåíò èç âåêòîðà ïàòðîíîâ, ÷òîáû åãî íå ðàçðÿäèëî
      ChangeAmmoVectorStart(wpn, sizeof(CCartridge));
    end;
  end;

  //Åñëè òåêóùèé òèï ïàòðîíîâ íå ñîîòâåòñòâóåò òîìó, êîòîðûé áóäåì çàðÿæàòü - ðàçðÿäèì îðóæèå
  need_unload:=false;
  if IsGrenadeMode(wpn) then begin
    cnt:=GetAmmoInGLCount(wpn);
    if cnt > 0 then begin
      for i:=0 to cnt - 1 do begin
        if GetCartridgeType(GetGrenadeCartridgeFromGLVector(wpn, i)) <> GetAmmoTypeIndex(wpn) then begin
          need_unload:=true;
          break;
        end;
      end;
    end;
  end else begin
    cnt:=GetAmmoInMagCount(wpn);
    if cnt > 0 then begin
      for i:=0 to cnt - 1 do begin
        if GetCartridgeType(GetCartridgeFromMagVector(wpn, i)) <> GetAmmoTypeIndex(wpn) then begin
          need_unload:=true;
          break;
        end;
      end;
    end;
  end;

  if need_unload then begin
    virtual_CWeaponMagazined__UnloadMagazine(wpn, true);
  end;

  if (buf<>nil) and buf.is_firstlast_ammo_swapped then begin
    //Îòêàòûâàåì ñäåëàííûå õàêîì èçìåíåíèÿ â âåêòîðå - íåðàçðÿæåííûé ïàòðîí èç ïàòðîííèêà ìàãè÷åñêèì îáðàçîì ïîÿâëÿåòñÿ îáðàòíî
    ChangeAmmoVectorStart(wpn, (-1)*sizeof(CCartridge));
  end;  
end;

procedure CWeaponMagazined__ReloadMagazine_OnUnloadMag_Patch(); stdcall;
asm
  pushad
    push esi
    call PerformUnloadAmmo
  popad
  @finish:
end;

procedure CWeaponMagazined__ReloadMagazine_OnFinish(wpn:pointer); stdcall;
var
  buf:WpnBuf;
begin
  buf:=GetBuffer(wpn);
  if (buf<>nil) and (buf.is_firstlast_ammo_swapped) then begin
    buf.is_firstlast_ammo_swapped:=false;
    SwapFirstLastAmmo(wpn);
  end;
end;

procedure CWeaponMagazined__ReloadMagazine_OnFinish_Patch(); stdcall;
asm
  pushad
    push esi
    call CWeaponMagazined__ReloadMagazine_OnFinish
  popad

  pop esi
  pop ebp
  add esp, $48
end;


{$ifdef DISABLE_AUTOAMMOCHANGE}
procedure CWeaponmagazined__TryReload_Patch();stdcall;
asm
  //ïðîâåðÿåì, áûëà ëè îò þçåðà êîìàíäà íà ñìåíó ðåæèìà

  cmp byte ptr [esi+$6C7], $FF //if m_set_next_ammoType_on_reload<>-1 then jmp
  jne @need_change

  //Åñëè â ìàãàçèíå ïóñòî - èìååò ñìûñë àâòîìàòîì ñìåíèòü òèï, äàáû íå áûëî çàòóïîâ þçåðîâ
  push eax //ñîõðàíÿåì âàæíîå
  push esi
  call GetCurrentAmmoCount
  test eax, eax
  pop eax //âîññòàíîâèì ñîõðàíåííîå
  je @need_change

  mov eax, 0                    //ãîâîðèì, ÷òî ó îðóæèÿ 0 äîñòóïíûõ òèïîâ ïàòðîíîâ ;)

  @need_change:
  //äåëàåì âûðåçàííîå
  sar eax, 02
  test al, al
  ret
end;

procedure CWeaponShotgun__HaveCartridgeInInventory_DisableAutoAmmoChange_Patch(); stdcall;
asm
  movzx ebp,byte ptr [esp+$14] //original
  mov edi, eax //original
  cmp edi, ebp //orig check: (ac<cnt); ac = edi, cnt = ebp
  jae @finish

  cmp byte ptr [esi+$6c7], $FF // åñëè èãðîê íàæàë êíîïêó ñìåíû - ðàçðåøàåì ñìåíó
  jne @allowed_change

  cmp edi, 0 // åñëè â ðþêçàêå åùå åñòü ïàòðîíû òåêóùåãî òèïà (ac>0), çàïðåùàåì àâòîñìåíó
  jne @not_allowed_change

  push eax //ñîõðàíÿåì âàæíîå
  push esi
  call GetCurrentAmmoCount
  test eax, eax
  pop eax //âîññòàíîâèì ñîõðàíåííîå
  jne @not_allowed_change


  @allowed_change: // Ìîæåì ìåíÿòü òèï ïàòðîíîâ - íàäî çàãíàòü íàñ â öèêë ïåðåáîðà íàëè÷èÿ ðàçëè÷íûõ òèïîâ  (ò.å. êàê â îðèãèíàëå)
  xor ecx, ecx
  cmp ecx, 1
  jmp @finish

  @not_allowed_change: // íå ìîæåì ìåíÿòü òèï ïàòðîíîâ - íàäî âåðíóòü ðåçóëüòàò óñëîâèÿ (ac>=cnt)
  //Íî åñëè ìû ïîéäåì ìèìî öèêëà, òî âñåãäà ïîëó÷èì âîçâðàùåíèå true èç-çà îïòèìèçàöèè êîìïèëÿòîðà!
  //Âûâîä - ñðàâíèâàåì ñàìè è âîçâðàùàåìñÿ èç âûçûâàþùåé ôóíêöèè
  xor eax, eax
  cmp edi, ebp //ac = edi, cnt = ebp
  jb @retx2
  inc eax
  @retx2:
  pop ecx //ret addr
  pop edi
  pop ebp
  pop esi
  ret 4 // ret FROM CWeaponShotgun::HaveCartridgeInInventory

  @finish:
end;

{$endif}

//---------------------------------Ïàòðîíû â ïàòðîííèêå äëÿ äðîáîâèêîâ----------------------------

function CWeaponShotgun__OnAnimationEnd_OnAddCartridge(wpn:pointer):boolean; stdcall;
//âîçâðàùàåò, ñòîèò ëè ïðîäîëæàòü íàáèâàòü ïàòðîíû â TriStateReload, èëè õâàòèò óæå :)
var
  buf:WpnBuf;
begin
  buf:=GetBuffer(wpn);
  if buf<>nil then begin
    if not buf.IsReloaded then begin
      virtual_CWeaponShotgun__AddCartridge(wpn, 1);
      if buf.IsAmmoInChamber() and buf.SaveAmmoInChamber() then begin
        SwapLastPrevAmmo(wpn);
      end;
    end;
  end else begin
    virtual_CWeaponShotgun__AddCartridge(wpn, 1); //äàíü îðèãèíàëüíîìó êîäó ;)
  end;
  result:=CWeaponShotgun__HaveCartridgeInInventory(wpn, 1);
end;

procedure CWeaponShotgun__OnAnimationEnd_OnAddCartridge_Patch(); stdcall;
asm
  pushad
    sub esi, $2e0
    push esi
    call CWeaponShotgun__OnAnimationEnd_OnAddCartridge
    cmp al, 01
  popad
end;

//-----------------------------------------anm_close â ñëó÷àå ðó÷íîãî ïðåðûâàíèÿ ðåëîàäà----------------------------
procedure CWeaponShotgun__Action_OnStopReload(wpn:pointer); stdcall;
begin
  if (GetSubState(wpn)=EWeaponSubStates__eSubStateReloadEnd) or (IsWeaponJammed(wpn)) then begin //???ïåðâîå íèêîãäà íå âûïîëíèòñÿ - ñì èñõîäíèê äâèãà???
    exit;
  end;
  if not IsActionProcessing(wpn) then begin
    SetSubState(wpn, EWeaponSubStates__eSubStateReloadEnd);
    virtual_CHudItem_SwitchState(wpn,EWeaponStates__eReload);
  end else begin
    SetActorKeyRepeatFlag(kfFIRE, true);
  end;
end;

procedure CWeaponShotgun__Action_OnStopReload_Patch(); stdcall;
asm
  pushad
  push esi
  call CWeaponShotgun__Action_OnStopReload
  popad
end;

//----------------------------------------------äîáàâëåíèå ïàòðîíà â open-------------------------------------------
procedure CWeaponMagazined__OnAnimationEnd_anm_open(wpn:pointer); stdcall;
var
  buf:WpnBuf;
begin
  if IsWeaponJammed(wpn) then begin
    SetWeaponMisfireStatus(wpn, false);
    SetSubState(wpn, EWeaponSubStates__eSubStateReloadBegin);
    virtual_CHudItem_SwitchState(wpn, EHudStates__eIdle);
    exit;
  end;

  SetSubState(wpn, EWeaponSubStates__eSubStateReloadInProcess); //âûðåçàííîå
  buf:=GetBuffer(wpn);
  if (buf<>nil) and buf.AddCartridgeAfterOpen() then begin
    CWeaponShotgun__OnAnimationEnd_OnAddCartridge(wpn);
  end;
  virtual_CHudItem_SwitchState(wpn, EWeaponStates__eReload);
end;

procedure CWeaponMagazined__OnAnimationEnd_anm_open_Patch(); stdcall;
asm
  pushad
  sub esi, $2e0
  push esi
  call CWeaponMagazined__OnAnimationEnd_anm_open
  popad
end;

//-------------------------------------------------------Óñëîâèå íà ðàñêëèí áåç ïàòðîíîâ â èíâåíòàðå-----------------------------------------
function CWeaponShotgun_Needreload(wpn:pointer):boolean; stdcall;
begin
  result:= (IsWeaponJammed(wpn) or CWeaponShotgun__HaveCartridgeInInventory(wpn, 1));
end;

procedure CWeaponShotgun__TriStateReload_Needreload_Patch(); stdcall;
asm
  pushad
    push esi
    call CWeaponShotgun_Needreload
    test al, al
  popad
end;

procedure CWeaponShotgun__OnStateSwitch_Needreload_Patch(); stdcall;
asm
  pushad
    push edi
    call CWeaponShotgun_Needreload
    test al, al
  popad
end;


procedure CWeaponMagazined__TryReload_hasammo_Patch(); stdcall;
asm
  cmp [esi+$690], 00 //original
  jne @finish
  //cmp byte ptr [esi+$7f8], 1 //àêòèâåí ëè ïîäñòâîë ñåé÷àñ
  pushad
    push esi
    call IsGrenadeMode
    cmp al, 1
  popad

  @finish:
end;
//------------------------------------------------------------------------------------------------------------------
procedure CWeapon__Weight_CalcAmmoWeight(wpn:pointer; total_weight:psingle); stdcall;
var
  weight:single;
  cnt, i:cardinal;
  c:pCCartridge;
  box_weight, box_count:single;
  sect:PChar;
begin
  if dynamic_cast(wpn, 0, RTTI_CWeapon, RTTI_CWeaponMagazined, false) = nil then exit;

  weight:=0;

  cnt:=GetAmmoInMagCount(wpn);
  if cnt>0 then begin
    for i:=0 to cnt-1 do begin
      c:=GetCartridgeFromMagVector(wpn, i);
      if c<>nil then begin
        sect:= GetCartridgeSection(c);
        if sect<>nil then begin
          box_count:=game_ini_r_single_def(sect, 'box_size', 1);
          box_weight:=game_ini_r_single_def(sect, 'inv_weight', 0);

          weight:=weight+ (box_weight/box_count);
        end;
      end;
    end;
  end;

  cnt:=GetAmmoInGLCount(wpn);
  if cnt>0 then begin
    for i:=0 to cnt-1 do begin
      c:=GetGrenadeCartridgeFromGLVector(wpn, i);
      if c<>nil then begin
        sect:= GetCartridgeSection(c);
        if sect<>nil then begin
          box_count:=game_ini_r_single_def(sect, 'box_size', 1);
          box_weight:=game_ini_r_single_def(sect, 'inv_weight', 0);

          weight:=weight+ (box_weight/box_count);
        end;
      end;
    end;
  end;

  total_weight^:=total_weight^+weight;
end;


procedure CWeapon__Weight_CalcAmmoWeight_Patch(); stdcall;
asm
  lea eax, [esp+8]
  pushad

  push eax
  push esi
  call CWeapon__Weight_CalcAmmoWeight


  xor eax, eax
  cmp eax, 0 //÷òîáû ñòàíäàðòíûé íåäîêîä ïîäñ÷åòà äàæå íå äóìàë âûïîëíÿòüñÿ!
  popad;
end;

function GetTotalGrenadesCountInInventory(wpn:pointer):cardinal;stdcall;
var
  g_m:boolean;
  cnt, i:cardinal;
  gl_status:cardinal;
begin
  gl_status:=GetGLStatus(wpn);
  if (gl_status=0) or ((gl_status=2) and not IsGLAttached(wpn)) then begin
    result:=0;
    exit;
  end;

  g_m:=IsGLEnabled(wpn);
  cnt:=GetGLAmmoTypesCount(wpn);
  result:=0;

  for i:=0 to cnt-1 do begin
    if g_m then
      result:=result+cardinal(CWeapon__GetAmmoCount(wpn, byte(i)))
    else
      result:=result+cardinal(CWeaponMagazinedWGrenade__GetAmmoCount2(wpn, byte(i)));
  end;
end;

procedure CWeaponMagazinedWGrenade__GetBriefInfo_GrenadesCount_Patch(); stdcall;
asm
  push ecx
  lea ecx, [esp]
  pushad
    push ecx

    push ebp
    call GetTotalGrenadesCountInInventory

    pop ecx
    mov [ecx], eax
  popad
  pop eax
end;

function CWeaponMagazined_FillBriefInfo(wpn:pointer; bi:pII_BriefInfo):boolean; stdcall;
//no GL
var
  ammo_sect:PChar;
  s:string;
  cnt, ammos, i, current:cardinal;
  queue:integer;
begin
  ammo_sect:= GetMainCartridgeSectionByType(wpn, GetAmmoTypeIndex(wpn, false));

  assign_string(@bi.name, game_ini_read_string(ammo_sect, 'inv_name_short'));
  assign_string(@bi.icon, ammo_sect);
  s:=inttostr(GetAmmoInMagCount(wpn));
  assign_string(@bi.cur_ammo, PChar(s));

  cnt:=GetMainAmmoTypesCount(wpn);
  if cnt>0 then begin
    current:=GetAmmoTypeIndex(wpn, false);
    s:=inttostr(CWeapon__GetAmmoCount(wpn, current));
    assign_string(@bi.fmj_ammo, PChar(s));
    if cnt>1 then begin
      ammos:=0;
      for i:=0 to cnt-1 do begin
        if i<>current then begin
          ammos:=ammos+cardinal(CWeapon__GetAmmoCount(wpn, i));
        end;
      end;
      s:=inttostr(ammos);
      assign_string(@bi.ap_ammo, PChar(s));
    end else begin
      assign_string(@bi.ap_ammo, ' ');
    end;
  end else begin
    assign_string(@bi.fmj_ammo, ' ');
    assign_string(@bi.ap_ammo, ' ');    
  end;

  if HasDifferentFireModes(wpn) then begin
    queue:=CurrentQueueSize(wpn);
    if queue<0 then begin
      s:='A';
    end else begin
      s:=inttostr(queue)
    end;
    assign_string(@bi.fire_mode, PChar(s));
  end else begin
    assign_string(@bi.fire_mode, ' ');
  end;
  assign_string(@bi.grenade, ' '); 

  result:=true;
end;


function CWeaponMagazinedWGrenade_FillBriefInfo(wpn:pointer; bi:pII_BriefInfo):boolean; stdcall;
var
  ammotypes, i:cardinal;
  ammo_cnt, queue:integer;
  g_m:boolean;
  gl_status:cardinal;
  ammo_sect:PChar;
  current:byte;
  s:string;  
begin
  g_m:=IsGrenadeMode(wpn);

  if not g_m then begin
    result:=CWeaponMagazined_FillBriefInfo(wpn, bi);
  end else begin
    current:=GetAmmoTypeIndex(wpn, false);
    ammo_sect:= GetGLCartridgeSectionByType(wpn, current);
    assign_string(@bi.name, game_ini_read_string(ammo_sect, 'inv_name_short'));
    assign_string(@bi.icon, ammo_sect);
    s:=inttostr(GetAmmoInGLCount(wpn));
    assign_string(@bi.cur_ammo, PChar(s));

    ammotypes:=GetGLAmmoTypesCount(wpn);
    if ammotypes>0 then begin
      s:=inttostr(CWeapon__GetAmmoCount(wpn, current));
      assign_string(@bi.fmj_ammo, PChar(s));
      if ammotypes>1 then begin
        ammo_cnt:=0;
        for i:=0 to ammotypes-1 do begin
          if i<>current then begin
            ammo_cnt:=ammo_cnt+cardinal(CWeapon__GetAmmoCount(wpn, i));
          end;
        end;
        s:=inttostr(ammo_cnt);
        assign_string(@bi.ap_ammo, PChar(s));
      end else begin
        assign_string(@bi.ap_ammo, ' ');
      end;
    end else begin
      assign_string(@bi.fmj_ammo, ' ');
      assign_string(@bi.ap_ammo, ' ');
    end;

    if HasDifferentFireModes(wpn) then begin
      queue:=CurrentQueueSize(wpn);
      if queue<0 then begin
        s:='A';
      end else begin
        s:=inttostr(queue)
      end;
      assign_string(@bi.fire_mode, PChar(s));
    end else begin
      assign_string(@bi.fire_mode, ' ');
    end;
    result:=true;
  end;

  //ïåðåîïðåäåëÿåì ñòðîêó ÷èñëà ãðåí
  gl_status:=GetGLStatus(wpn);
  if (gl_status=1) or ((gl_status=2) and IsGLAttached(wpn)) then begin
    ammotypes:=GetGLAmmoTypesCount(wpn);
    ammo_cnt:=0;
    for i:=0 to ammotypes-1 do begin
      if not g_m then
        ammo_cnt:=ammo_cnt+CWeaponMagazinedWGrenade__GetAmmoCount2(wpn, i)
      else
        ammo_cnt:=ammo_cnt+CWeapon__GetAmmoCount(wpn, i);
    end;
    if ammo_cnt = 0 then begin
      assign_string(@bi.grenade, 'X');
    end else begin
      assign_string(@bi.grenade, PChar(inttostr(ammo_cnt)));
    end;
  end else begin
    assign_string(@bi.grenade, ' ');
  end;
end;

procedure CWeaponMagazined__GetBriefInfo_Replace_Patch(); stdcall;
asm
  mov eax, [esp+4]
  pushad
    push eax
    push ecx
    call CWeaponMagazined_FillBriefInfo;
  popad

  mov eax, 1
  ret 4
end;

procedure CWeaponMagazinedWGrenade__GetBriefInfo_Replace_Patch(); stdcall;
asm
  mov eax, [esp+4]
  pushad
    push eax
    push ecx
    call CWeaponMagazinedWGrenade_FillBriefInfo;
  popad

  mov eax, 1
  ret 4
end;

procedure CWeaponMagazinedWGrenade__PerformSwitchGL_ammoinverse_Patch(); stdcall;
asm
  //ñâîïàåì ïàòðîíû

  mov edi, [esi+$6C8]
  mov ebx, [esi+$7EC]
  mov [esi+$6C8], ebx
  mov [esi+$7EC], edi

  mov edi, [esi+$6CC]
  mov ebx, [esi+$7F0]
  mov [esi+$6CC], ebx
  mov [esi+$7F0], edi

  mov edi, [esi+$6D0]
  mov ebx, [esi+$7F4]
  mov [esi+$6D0], ebx
  mov [esi+$7F4], edi

  //äåëàåì îñòàòîê ôóíêöèè
  mov eax, [esi+$6cc]
  sub eax, [esi+$6c8]

  xor edx, edx
  mov ebx, $3c;
  div ebx

  mov [esi+$690], eax


  mov [esi+$69C], 0
  //âàëèì
  pop edi
  pop esi
  pop ebp
  pop ebx
  add esp, $4C
  ret
end;


function Init:boolean;
var
    debug_bytes:array of byte;
    addr:cardinal;
begin
  result:=false;
  setlength(debug_bytes, 6);
  ////////////////////////////////////////////////////
  //[bug]îòêëþ÷àåì áàã ñ ìîìåíòàëüíîé ñìåíîé òèïà ïàòðîíîâ ïðè ïåðåçàðÿäêå, êîãäà ó íàñ íå õâàòàåò ïàòðîíîâ òåêóùåãî òèïà äî ïîëíîãî ìàãàçèíà
  //[bug]Îíî æå ïðîÿâëÿåòñÿ, åñëè ó îðóæèÿ, ó êîòîðîãî íåïîëíûé ìàãàçèí îäíîãî òèïà ïàòðîíîâ, è òàêîãî òèïà â èíâåíòàðå áîëüøå íåò, ïîïðîáîâàòü ñìåíèòü òèï è, íå äîæèäàÿñü îêîí÷àíèÿ àíèìû,  âûáðîñèòü
  //ïîñëå ïîäúåìà îðóæèå íå áóäåò ðåàãèðîâàòü íà êëàâèøó ñìåíû òèïà
  // ïðè÷èíà â òîì, ÷òî â CWeaponMagazined::TryReload ìû ïðèñâàèâàåì çíà÷åíèå ÷ëåíó m_ammoType âìåñòî m_set_next_ammoType_on_reload
  debug_bytes[0]:=$C7;
  if not WriteBufAtAdr(xrGame_addr+$2D0185, @debug_bytes[0],1) then exit;
  if not WriteBufAtAdr(xrGame_addr+$2DE84B, @debug_bytes[0],1) then exit;  //CWeaponShotgun::HaveCarteidgeInInventory, ïîòîì âñå ðàâíî ïåðåçàïèñûâàåì, íî ïóñòü áóäåò


  //ðåøàåò, ñêîëüêî ïàòðîíîâ íàäî çàðÿäèòü â ðåëîàäå è äåëàåò ñàì ðåëîàä
  addr:=xrGame_addr+$2CCD94;
  if not WriteJump(addr, cardinal(@CWeaponMagazined__OnAnimationEnd_DoReload_Patch), 20, true) then exit;

  //îïöèîíàëüíîå äîáàâëåíèå ïàòðîíà ïîñëå anm_open
  addr:=xrGame_addr+$2DE41C;
  if not WriteJump(addr, cardinal(@CWeaponMagazined__OnAnimationEnd_anm_open_Patch), 15, true) then exit;

  //Ïðè ñìåíå òèïà ïàòðîíîâ ìàãàçèí ðàçðÿæàåòñÿ - çàñòàâëÿåì îñòàâèòü ïîñëåäíèé ïàòðîí íåðàçðÿæåííûì
  nop_code(xrGame_addr+$2D10D8, 2); //óáèðàåì óñëîâèå íà íåðàâåíñòâî ñåêöèé ïîñëåäíåãî ïàòðîíà è çàðÿæàåìîãî
  addr:=xrGame_addr+$2D1106;
  if not WriteJump(addr, cardinal(@CWeaponMagazined__ReloadMagazine_OnUnloadMag_Patch), 6, true) then exit;
  //ñâîïèì ïåðâûé è ïîñëåäíèé ïàòðîí, åñëè ó íàñ áûëà ñìåíà òèïà 
  addr:=xrGame_addr+$2D125F;
  if not WriteJump(addr, cardinal(@CWeaponMagazined__ReloadMagazine_OnFinish_Patch), 6, false) then exit;

  //îòêëþ÷àåì äîáàâëåíèå "ëèøíåãî" ïàòðîíà ïðè ïðåðûâàíèè ðåëîàäà äðîáîâèêà +çàñòàâëÿåì èãðàòüñÿ anm_close (â CWeaponShotgun::Action)
  addr:=xrGame_addr+$2DE374;
  if not WriteJump(addr, cardinal(@CWeaponShotgun__Action_OnStopReload_Patch), 30, true) then exit;

  //ïàòðîí â ïàòðîííèêå+àíèìàöèÿ ðàñêëèíèâàíèÿ+îòâå÷àåò çà äîáàâëåíèå ïàòðîíà â ìàãàçèí
  addr:=xrGame_addr+$2DE3ED;
  if not WriteJump(addr, cardinal(@CWeaponShotgun__OnAnimationEnd_OnAddCartridge_Patch), 22, true) then exit;

  //èçìåíèì óñëîâèå, êîòîðîå íå äàåò ðàñêëèíèâàòü CWeaponMagazined, åñëè ïàòðîíîâ ê íåìó íåò íè â èíâåíòàðå, íè â ìàãàçèíå
  //îíî ñóùåñòâåííî òîëüêî ïðè ïåðåçàðÿäêå â ðåæèìå ïîäñòâîëà
  addr:=xrGame_addr+$2D00AD;
  if not WriteJump(addr, cardinal(@CWeaponMagazined__TryReload_hasammo_Patch), 7, true) then exit;


  //äàäèì âîçìîæíîñòü ðàñêëèíèâàòü äðîáîâèê, êîãäà â èíâåíòàðå íåò ïàòðîíîâ
  addr:=xrGame_addr+$2DE94A;
  if not WriteJump(addr, cardinal(@CWeaponShotgun__TriStateReload_Needreload_Patch), 11, true) then exit;
  addr:=xrGame_addr+$2DE9D1;
  if not WriteJump(addr, cardinal(@CWeaponShotgun__OnStateSwitch_Needreload_Patch), 11, true) then exit;
  addr:=xrGame_addr+$2DEA19;
  if not WriteJump(addr, cardinal(@CWeaponShotgun__OnStateSwitch_Needreload_Patch), 11, true) then exit;
  //addr:=xrGame_addr+$2DEA00;
  //if not WriteJump(addr, cardinal(@CWeaponShotgun__OnStateSwitch_Needreload_Patch), 11, true) then exit;


{$ifdef DISABLE_AUTOAMMOCHANGE}
  addr:=xrGame_addr+$2D00FF;
  if not WriteJump(addr, cardinal(@CWeaponMagazined__TryReload_Patch), 5, true) then exit;

  addr:=xrGame_addr+$2DE7E2;
  if not WriteJump(addr, cardinal(@CWeaponShotgun__HaveCartridgeInInventory_DisableAutoAmmoChange_Patch), 9, true) then exit;
{$endif}

  //[bug] áàã ñ íåïðàâèëüíûì ðàñ÷åòîì âåñà îðóæèÿ â CWeapon::Weight: íå ó÷èòûâàåòñÿ âîçìîæíîñòü íàëè÷èÿ â ìàãàçèíå áîåïðèïàñîâ ðàçíûõ òèïîâ, à òàêæå çàðÿäîâ â ïîäñòâîëüíèêå
  addr:=xrGame_addr+$2BE9B7;
  if not WriteJump(addr, cardinal(@CWeapon__Weight_CalcAmmoWeight_Patch), 7, true) then exit;

  //[bug] áàã ñ îïðåäåëåíèåì ÷èñëà ãðàíàò äëÿ ïîäñòâîëà - îïðåäåëÿåòñÿ òîëüêî ÷èñëî äëÿ 1ãî òèïà, îñòàëüíûå èãíîðÿòñÿ
  addr:=xrGame_addr+$2D2562;
  if not WriteJump(addr, cardinal(@CWeaponMagazinedWGrenade__GetBriefInfo_GrenadesCount_Patch), 17, true) then exit;


  //ïåðåäåëêà ñõåìû BriefInfo
  addr:=xrGame_addr+$2CE360;
  if not WriteJump(addr, cardinal(@CWeaponMagazined__GetBriefInfo_Replace_Patch), 5, false) then exit;
  addr:=xrGame_addr+$2D2110;
  if not WriteJump(addr, cardinal(@CWeaponMagazinedWGrenade__GetBriefInfo_Replace_Patch), 5, false) then exit;


  //[bug] áàã ñ èíâåðñèåé ïîðÿäêà ïàòðîíîâ â ìàãàçèíå ïðè ïåðåêëþ÷åíèè íà ïîäñòâîë è îáðàòíî - thanks to Shoker
  addr:=xrGame_addr+$2D3810;
  if not WriteJump(addr, cardinal(@CWeaponMagazinedWGrenade__PerformSwitchGL_ammoinverse_Patch), 6, false) then exit;


  setlength(debug_bytes, 0);  
  result:=true;

end;

end.
