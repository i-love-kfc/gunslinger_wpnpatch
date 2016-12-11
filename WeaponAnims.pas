unit WeaponAnims;

//�� ������ - �� ����������!

interface
function Init:boolean;
function ModifierStd(wpn:pointer; base_anim:string):string;stdcall;

implementation
uses BaseGameData, WpnUtils, GameWrappers, ActorUtils, WeaponAdditionalBuffer, math;

var
  anim_name:string;
  jump_addr:cardinal;

procedure ModifierGL(wpn:pointer; var anm:string);
begin
  if (GetGLStatus(wpn)=1) or IsGLAttached(wpn) then begin
    if IsGLEnabled(wpn) then
      anm:=anm+'_g'
    else
      anm:=anm+'_w_gl';
  end;
end;

procedure ModifierMoving(wpn:pointer; actor:pointer; var anm:string);
begin
  if GetActorActionState(actor, actMovingForward or actMovingBack or actMovingLeft or actMovingRight) then begin
    anm:=anm+'_moving';
    if GetActorActionState(actor, actMovingForward) then begin
      anm:=anm+'_forward';
    end;
    if GetActorActionState(actor, actMovingBack) then begin
      anm:=anm+'_back';
    end;
    if GetActorActionState(actor, actMovingLeft) then begin
      anm:=anm+'_left';
    end;
    if GetActorActionState(actor, actMovingRight) then begin
      anm:=anm+'_right';
    end;
  end;
end;

procedure ModifierBM16(wpn:pointer; var anm:string);
var cnt:integer;
begin
  if GetClassName(wpn) = 'WP_BM16' then begin
    cnt:=GetAmmoInMagCount(wpn);
    if cnt<=0 then
      anim_name:=anim_name+'_0'
    else if cnt=1 then
      anim_name:=anim_name+'_1'
    else
      anim_name:=anim_name+'_2';
  end;
end;


//------------------------------------------------------------------------------anm_idle(_sprint, _moving, _aim)---------------------------------------
function anm_idle_selector(wpn:pointer):pchar;stdcall;
var
  hud_sect:PChar;
  actor:pointer;
  canshoot:boolean;
  cls:string;
  buf:WpnBuf;
  tmppchar:PChar;
begin
  hud_sect:=GetHUDSection(wpn);
  anim_name:='anm_idle';
  actor:=GetActor();
  cls:=GetClassName(wpn);
  //���� � ��� �������� - �� �����, �� � ������ �������� ������ ���
  if (actor<>nil) and (actor=GetOwner(wpn)) then begin
    canshoot:=WpnCanShoot(PChar(cls));
    //--------------------------������������ �������� ������---------------------------------------
    //���� ����� � ������ ������������ - ���������� ���������� ����������� �������� aim
    if (canshoot or (cls='WP_BINOC')) and IsAimNow(wpn) then begin
      anim_name:=anim_name+'_aim';
      ModifierMoving(wpn, actor, anim_name);
      
    //��������� �� ������������ ������:
    end else if GetActorActionState(actor, actSprint, true) and not GetActorActionState(actor, actSprint) then begin
      //����� �� �������
      anim_name:=anim_name+'_sprint_end';
    end else if GetActorActionState(actor, actSprint) then begin
      anim_name:=anim_name+'_sprint';
      if not GetActorActionState(actor, actSprint, true) then anim_name:=anim_name+'_start';
    end else begin
      ModifierMoving(wpn, actor, anim_name);
      if GetActorActionState(actor, actCrounch) then begin
        anim_name:=anim_name+'_crounch';
      end;
      if GetActorActionState(actor, actSlow) then begin
        anim_name:=anim_name+'_slow';
      end;
    end;
  //----------------------------------������������ ��������� ������---------------------------------------------------- 

    if canshoot then begin
        //���� ������ ��������� - ������ �������� �������� ��� ���������
        if IsWeaponJammed(wpn) then begin
          anim_name:=anim_name+'_jammed';
        end else if (GetAmmoInMagCount(wpn)<=0) and (cls<>'WP_BM16') then begin
          anim_name:=anim_name+'_empty';
        end;

        ModifierGL(wpn, anim_name);
    end;
  end;
  //���������� ����� ����������� �������
  ModifierBM16(wpn, anim_name);

  if not game_ini_line_exist(hud_sect, PChar(anim_name)) then begin
    log('Section ['+hud_sect+'] has no motion alias defined ['+anim_name+']');
    anim_name:='anm_idle';
    ModifierBM16(wpn, anim_name);
  end;
  result:=PChar(anim_name);
  MakeLockByConfigParam(wpn, hud_sect, PChar('lock_time_'+anim_name));
end;

procedure anm_idle_std_patch();stdcall;
begin
  asm
    push 0                  //�������� ����� ��� �������� �����
    pushad
    pushfd
    push esi
    call anm_idle_selector  //�������� ������ � ������ �����
    mov ecx, [esp+$28]      //���������� ����� ��������
    mov [esp+$28], eax      //������ �� ��� ����� �������������� ������
    mov [esp+$24], ecx      //���������� ����� �������� �� 4 ����� ���� � �����
    popfd
    popad
    ret
  end;
end;

procedure anm_idle_sub_patch();stdcall;
begin
  asm

    sub esi, $2E0
    call anm_idle_std_patch
    add esi, $2E0

    push eax
    push ebx
    mov eax, [esp+8]
    mov ebx, [esp+$c]
    mov [esp+8], ebx
    mov [esp+$c], eax
    pop ebx
    pop eax

  end;
end;
//------------------------------------------------------------------------------anm_show/hide/bore/switch_*-----------------------
function ModifierStd(wpn:pointer; base_anim:string):string;stdcall;
var
  hud_sect:PChar;
  actor:pointer;
  cls:string;
begin
  hud_sect:=GetHUDSection(wpn);
  actor:=GetActor();
  //���� � ��� �������� - �� �����, �� � ������ �������� ������ ���
  if (actor<>nil) and (actor=GetOwner(wpn)) then begin
  //----------------------------------������������ ��������� ������----------------------------------------------------
    //���� ������� ���� - ������ ������ empty, ���� �����
    if WpnCanShoot(PChar(GetClassName(wpn))) then begin
      cls:=GetClassName(wpn);
      if IsWeaponJammed(wpn) then begin
        base_anim:=base_anim+'_jammed';
      end else if (GetAmmoInMagCount(wpn)<=0) and (cls<>'WP_BM16') then begin
        base_anim:=base_anim+'_empty';
      end;

      ModifierGL(wpn, base_anim);
    end;
  end;

  ModifierBM16(wpn, base_anim);
  if not game_ini_line_exist(hud_sect, PChar(base_anim)) then begin
    log('Section ['+hud_sect+'] has no motion alias defined ['+base_anim+']');
    base_anim:='anm_reload';
    ModifierBM16(wpn, base_anim);
  end;
  result:=base_anim;
end;

function anm_std_selector(wpn:pointer; base_anim:PChar):pchar;stdcall;
begin
  anim_name := ModifierStd(wpn, base_anim);
  result:=PChar(anim_name);
  MakeLockByConfigParam(wpn, GetHUDSection(wpn), PChar('lock_time_'+anim_name));
end;

procedure anm_show_std_patch();stdcall;
const anm_show:PChar = 'anm_show';
begin
  asm
    push 0                  //�������� ����� ��� �������� �����
    pushad
    pushfd
    push anm_show
    push esi
    call anm_std_selector  //�������� ������ � ������ �����
    mov ecx, [esp+$28]      //���������� ����� ��������
    mov [esp+$28], eax      //������ �� ��� ����� �������������� ������
    mov [esp+$24], ecx      //���������� ����� �������� �� 4 ����� ���� � �����
    popfd
    popad
    ret
  end;
end;

procedure anm_show_sub_patch();stdcall;
begin
  asm

    sub esi, $2E0
    call anm_show_std_patch
    add esi, $2E0

    push eax
    push ebx
    mov eax, [esp+8]
    mov ebx, [esp+$c]
    mov [esp+8], ebx
    mov [esp+$c], eax
    pop ebx
    pop eax

  end;
end;

procedure anm_hide_std_patch();stdcall;
const anm_hide:PChar = 'anm_hide';
begin
  asm
    push 0                  //�������� ����� ��� �������� �����
    pushad
    pushfd
    push anm_hide
    push esi
    call anm_std_selector  //�������� ������ � ������ �����
    mov ecx, [esp+$28]      //���������� ����� ��������
    mov [esp+$28], eax      //������ �� ��� ����� �������������� ������
    mov [esp+$24], ecx      //���������� ����� �������� �� 4 ����� ���� � �����
    popfd
    popad
    ret
  end;
end;

procedure anm_hide_sub_patch();stdcall;
begin
  asm

    sub esi, $2E0
    call anm_hide_std_patch
    add esi, $2E0

    push eax
    push ebx
    mov eax, [esp+8]
    mov ebx, [esp+$c]
    mov [esp+8], ebx
    mov [esp+$c], eax
    pop ebx
    pop eax

  end;
end;

procedure anm_bore_edi_patch();stdcall;
const anm_bore:PChar = 'anm_bore';
begin
  asm
    push 0                  //�������� ����� ��� �������� �����
    pushad
    pushfd
    push anm_bore
    sub edi, $2E0
    push edi
    call anm_std_selector  //�������� ������ � ������ �����
    mov ecx, [esp+$28]      //���������� ����� ��������
    mov [esp+$28], eax      //������ �� ��� ����� �������������� ������
    mov [esp+$24], ecx      //���������� ����� �������� �� 4 ����� ���� � �����
    popfd
    popad
    ret
  end;
end;

procedure anm_bore_std_patch();stdcall;
const anm_bore:PChar = 'anm_bore';
begin
  asm
    push 0                  //�������� ����� ��� �������� �����
    pushad
    pushfd
    push anm_bore
    push esi
    call anm_std_selector  //�������� ������ � ������ �����
    mov ecx, [esp+$28]      //���������� ����� ��������
    mov [esp+$28], eax      //������ �� ��� ����� �������������� ������
    mov [esp+$24], ecx      //���������� ����� �������� �� 4 ����� ���� � �����
    popfd
    popad
    ret
  end;
end;

procedure anm_bore_sub_patch();stdcall;
begin
  asm

    sub esi, $2E0
    call anm_bore_std_patch
    add esi, $2E0

    push eax
    push ebx
    mov eax, [esp+8]
    mov ebx, [esp+$c]
    mov [esp+8], ebx
    mov [esp+$c], eax
    pop ebx
    pop eax

  end;
end;

procedure anm_switch_sub_patch();stdcall;
const anm_switch:PChar = 'anm_switch';
begin
  asm
    push 0                  //�������� ����� ��� �������� �����
    pushad
    pushfd
    sub esi, $2E0
    push anm_switch
    push esi
    call anm_std_selector  //�������� ������ � ������ �����
    mov ecx, [esp+$28]      //���������� ����� ��������
    mov [esp+$28], eax      //������ �� ��� ����� �������������� ������
    mov [esp+$24], ecx      //���������� ����� �������� �� 4 ����� ���� � �����
    popfd
    popad
    ret
  end;
end;

function anm_shoot_g_selector(wpn:pointer; base_anim:PChar):pchar;stdcall;
var
  tmpstr:string;
  actor:pointer;
begin
  tmpstr:=base_anim;
  actor:=GetActor();
  //���� � ��� �������� - �� �����, �� � ������ �������� ������ ���
  if (actor<>nil) and (actor=GetOwner(wpn)) and IsAimNow(wpn) then begin
    tmpstr:=tmpstr+'_aim';
  end;
  result:=anm_std_selector(wpn, PChar(tmpstr));
end;

procedure anm_shoot_g_std_patch();stdcall;
const anm_shoot_g:PChar = 'anm_shoot';
begin
  asm
    push 0                  //�������� ����� ��� �������� �����
    pushad
    pushfd
    push anm_shoot_g
    push esi
    call anm_shoot_g_selector  //�������� ������ � ������ �����
    mov ecx, [esp+$28]      //���������� ����� ��������
    mov [esp+$28], eax      //������ �� ��� ����� �������������� ������
    mov [esp+$24], ecx      //���������� ����� �������� �� 4 ����� ���� � �����
    popfd
    popad
    ret
  end;
end;

procedure anm_reload_g_std_patch();stdcall;
const anm_reload_g:PChar = 'anm_reload';
begin
  asm
    push 0                  //�������� ����� ��� �������� �����
    pushad
    pushfd
    push anm_reload_g
    push esi
    call anm_std_selector  //�������� ������ � ������ �����
    mov ecx, [esp+$28]      //���������� ����� ��������
    mov [esp+$28], eax      //������ �� ��� ����� �������������� ������
    mov [esp+$24], ecx      //���������� ����� �������� �� 4 ����� ���� � �����
    popfd
    popad
    ret
  end;
end;

procedure anm_open_std_patch();stdcall;
const anm_open:PChar = 'anm_open';
begin
  asm
    push 0                  //�������� ����� ��� �������� �����
    pushad
    pushfd
    push anm_open
    push esi
    call anm_std_selector  //�������� ������ � ������ �����
    mov ecx, [esp+$28]      //���������� ����� ��������
    mov [esp+$28], eax      //������ �� ��� ����� �������������� ������
    mov [esp+$24], ecx      //���������� ����� �������� �� 4 ����� ���� � �����
    popfd
    popad
    ret
  end;
end;

procedure anm_close_std_patch();stdcall;
const anm_close:PChar = 'anm_close';
begin
  asm
    push 0                  //�������� ����� ��� �������� �����
    pushad
    pushfd
    push anm_close
    push esi
    call anm_std_selector  //�������� ������ � ������ �����
    mov ecx, [esp+$28]      //���������� ����� ��������
    mov [esp+$28], eax      //������ �� ��� ����� �������������� ������
    mov [esp+$24], ecx      //���������� ����� �������� �� 4 ����� ���� � �����
    popfd
    popad
    ret
  end;
end;

procedure anm_add_cartridge_std_patch();stdcall;
const anm_add_cartridge:PChar = 'anm_add_cartridge';
begin
  asm
    push 0                  //�������� ����� ��� �������� �����
    pushad
    pushfd
    push anm_add_cartridge
    push esi
    call anm_std_selector  //�������� ������ � ������ �����
    mov ecx, [esp+$28]      //���������� ����� ��������
    mov [esp+$28], eax      //������ �� ��� ����� �������������� ������
    mov [esp+$24], ecx      //���������� ����� �������� �� 4 ����� ���� � �����
    popfd
    popad
    ret
  end;
end;
//----------------------------------------------------------anm_shots------------------------------------------------
function anm_shots_selector(wpn:pointer):pchar;stdcall;
var
  hud_sect:PChar;
  actor:pointer;
begin
  hud_sect:=GetHUDSection(wpn);
  anim_name:='anm_shoot';
  actor:=GetActor();
  //���� � ��� �������� - �� �����, �� � ������ �������� ������ ���
  if (actor<>nil) and (actor=GetOwner(wpn)) then begin
    //----------------------------------������������ ��������� ������----------------------------------------------------
    if IsAimNow(wpn) then anim_name:=anim_name+'_aim';
    //----------------------------------������������ ��������� ������----------------------------------------------------
    if IsWeaponJammed(wpn) then begin
      anim_name:=anim_name+'_jammed';
    end else if GetAmmoInMagCount(wpn)=1 then
      anim_name:=anim_name+'_last'
    else if CurrentQueueSize(wpn)>1 then
      anim_name:=anim_name+'_queue';
    if (GetSilencerStatus(wpn)=1) or ((GetSilencerStatus(wpn)=2) and IsSilencerAttached(wpn)) then anim_name:=anim_name+'_sil';
    ModifierGL(wpn, anim_name);
  end;

  ModifierBM16(wpn, anim_name);
  if not game_ini_line_exist(hud_sect, PChar(anim_name)) then begin
    log('Section ['+hud_sect+'] has no motion alias defined ['+anim_name+']');
    anim_name:='anm_reload';
    ModifierBM16(wpn, anim_name);
  end;
  result:=PChar(anim_name);
  MakeLockByConfigParam(wpn, hud_sect, PChar('lock_time_'+anim_name));
end;

procedure anm_shots_std_patch();stdcall;
begin
  asm
    push 0                  //�������� ����� ��� �������� �����
    pushad
    pushfd
    push esi
    call anm_shots_selector  //�������� ������ � ������ �����
    mov ecx, [esp+$28]      //���������� ����� ��������
    mov [esp+$28], eax      //������ �� ��� ����� �������������� ������
    mov [esp+$24], ecx      //���������� ����� �������� �� 4 ����� ���� � �����
    popfd
    popad
    ret
  end;
end;

//---------------------------------------------------------anm_reload------------------------------------------------
function anm_reload_selector(wpn:pointer):pchar;stdcall;
var
  hud_sect:PChar;
  actor:pointer;
begin
  hud_sect:=GetHUDSection(wpn);
  anim_name:='anm_reload';
  actor:=GetActor();
  //���� � ��� �������� - �� �����, �� � ������ �������� ������ ���
  if (actor<>nil) and (actor=GetOwner(wpn)) then begin
    //----------------------------------������������ ��������� ������----------------------------------------------------
    if IsWeaponJammed(wpn) then begin
      anim_name:=anim_name+'_jammed';
      if GetAmmoInMagCount(wpn)=0 then anim_name:=anim_name+'_last';
      SetAmmoTypeChangingStatus(wpn, $FF);
    end else if GetAmmoInMagCount(wpn)<=0 then begin
      if GetClassName(wpn)<>'WP_BM16' then anim_name:=anim_name+'_empty'; //� ���������� � ��� _0 ����� ����������� ��������
    end else if GetAmmoTypeChangingStatus(wpn)<>$FF then begin
      anim_name:=anim_name+'_ammochange';
    end;

    ModifierGL(wpn, anim_name);
  end;

  ModifierBM16(wpn, anim_name);
  if not game_ini_line_exist(hud_sect, PChar(anim_name)) then begin
    log('Section ['+hud_sect+'] has no motion alias defined ['+anim_name+']');
    anim_name:='anm_reload';
    ModifierBM16(wpn, anim_name);
  end;
  result:=PChar(anim_name);
  MakeLockByConfigParam(wpn, hud_sect, PChar('lock_time_'+anim_name));
end;


procedure anm_reload_std_patch();stdcall;
begin
  asm
    push 0                  //�������� ����� ��� �������� �����
    pushad
    pushfd
    push esi
    call anm_reload_selector  //�������� ������ � ������ �����
    mov ecx, [esp+$28]      //���������� ����� ��������
    mov [esp+$28], eax      //������ �� ��� ����� �������������� ������
    mov [esp+$24], ecx      //���������� ����� �������� �� 4 ����� ���� � �����
    popfd
    popad
    ret
  end;
end;
//--------------------------------------------���� ��� �������� �������� ���������------------------------------
procedure GrenadeLauncherBugFix(); stdcall;
begin
  asm
    //�������� ���� �������� � �����
    mov [esp+4], 1
    // ������ ����������
    mov ecx, [esp]
    push ecx
    lea ecx, [esp+$1C];
    mov [esp+4], ecx
  end;
end;

procedure GrenadeAimBugFix(); stdcall;
begin
  asm
    //�������� ���� �������� � �����
    mov [esp+4], 1
    // ������ ����������
    mov ecx, [esp]
    push ecx
    lea ecx, [esp+$18];
    mov [esp+4], ecx
  end;
end;
//---------------------------------���� ��� ����������� ������������� ��� ����������� ���������-----------------------
procedure JammedBugFix(); stdcall;
begin
  asm
    cmp byte ptr [esi+$7f8], 1
    je @finish
    mov [esi+$45a], 0
    @finish:
  end;
end;
//------------���� ��� ����������� - ����� �� ���� �� ������� �������������� ����� �� ����------
procedure ReloadAnimPlayingPatch; stdcall;
begin
  asm
    pushad
      push esi
      call WeaponAdditionalBuffer.CanStartAction
      cmp al, 1
    popad
    jne @finish

    mov edx, [esi]
    mov eax, [edx+$188]
    mov ecx, esi
    call eax
    @finish:
    ret
  end;
end;
//--------------------------����������� ���� ��� ���� ������������ ������� ���������----------------------------------
//���������� ��������� ���� ������� � �����  
procedure SwitchAnimPlayingPatch; stdcall;
begin
  asm
    lea esi, [esi-$2e0];
    mov [esi+$2e8], 0
    mov [esi+$2e4], 0
    ret
  end;
end;

//� ���� -  �� ���� �������������, ����� �� ����
procedure SwitchAnimPlayingPatch2; stdcall;
begin
  asm
    //��������� ����������� ������������
    pushad
      push esi
      call WeaponAdditionalBuffer.CanStartAction
      cmp al, 1
    popad

    je @switch_ok
    //������������� ������ ������. ������� �� ������� � _����������_ �������� �����
    xor al, al
    mov [esi+$2e8], 0
    mov [esi+$2e4], 0
    pop esi     //���������� ������� ����� ��������
    pop esi
    ret
    
    @switch_ok:
    //������ ����������
    mov edx,[eax+$168]
    //������� � ���������� ���������
    ret
  end;
end;

//-----------���� ��� idle_slow - ����� ���� �������� �������� ����� �������� �� �������� ���� � ��������� � �.�.-----
procedure IdleSlowFixPatch(); stdcall;
begin
  asm
    //������ ���������� ���������
    and eax, $0F
    cmp [esp+$2C], eax
    //���� � ��� ���� ��������� ����� ����� - ������ ���� �� ������ 
    jne @finish
    //���� ��� �� ���������� ��������� ����� ����� ��������... ���������, �� ��������� �� ��� �.
    push eax
    push ebx

    mov eax, [ebx+$590]
    mov ebx, [ebx+$594]
    and eax, $3F
    and ebx, $3F
    cmp eax, ebx
    pop ebx
    pop eax
    
    @finish:
    ret
  end;
end;
//-------------------------------�� ���� ��������� bore, ���� �� ����� ��� ������-------------------------------------
procedure BoreAnimLockFix; stdcall;
begin
  asm
    pushad
      sub esi, $2e0
      push esi
      call WeaponAdditionalBuffer.CanStartAction
      cmp al, 1
    popad
    je @finish
    mov eax, 0
    cmp [esi-$2e0+$2e4], 4
    jne @finish
    cmp [esi-$2e0+$2e8], 4
    jne @finish
    mov [esi-$2e0+$2e4], 0
    mov [esi-$2e0+$2e8], 0
    @finish:
    not edx
    test dl, 01
    ret;
  end;
end;
//---------------------------------�� ���� ������� ������ ��� �������� ���� � ����------------------------------------
procedure HideAnimLockFix; stdcall;
begin
  asm
    lea ecx, [esi-$2e0]
    pushad
      push ecx
      call WeaponAdditionalBuffer.CanHideWeaponNow
      cmp al, 1
    popad
    je @no_lock
    mov [esi-$2e0+$2e4], 0
    mov [esi-$2e0+$2e8], 0
    ret
    @no_lock:
    call eax
    ret;
  end;
end;
//------------------------------------------��������� �������� � ��������� ��� ����-----------------------------------
procedure ShootGLAnimLockFix; stdcall;
begin
  asm
    pushad
      push esi
      call WeaponAdditionalBuffer.OnShoot_CanShootNow
      cmp al, 1
    popad
    je @nolock
    //� ��� ��� - ������ ������ � �� ��������� ��� ���������
    xor al, al
    pop edi     //�������� ������� ����� ��������
    pop edi
    pop esi
    ret 8

    @nolock:
    cmp [esi+$690], 0
    ret
  end;
end;
//---------------------------------------�� ���� ����������� ��� ����-------------------------------------------------
procedure AimAnimLockFix; stdcall;
begin
  asm
    push eax
    //���������� ZF=0, ���� �������� �� �����
    cmp byte ptr [esi+$494], 0
    je @finish
    xor al, al
    pushad
      push esi
      call WeaponAdditionalBuffer.CanAimNow
      cmp al, 1
    popad
    jne @compare
    mov al, 1
    @compare:
    cmp al, 0
    @finish:
    pop eax
    ret
  end;
end;
//---------------------------------------�� ���� �������� ��� ����-------------------------------------------------
procedure ShootAnimLockFix; stdcall;
begin
  //��������� ZF = 1, ���� ������ ��������
  asm
    pushad
      sub esi, $338
      push esi
      call WeaponAdditionalBuffer.OnShoot_CanShootNow
      cmp al, 0
    popad
    je @finish
    cmp [esi+$358], eax
    @finish:
    ret
  end;
end;
//---------------------------------------������ �������������� (� �� ������) �� ����-------------------------------------------------
procedure SprintAnimLockFix; stdcall;
asm
    pushad
      push ecx
      call WeaponAdditionalBuffer.CanSprintNow
      cmp al, 0
    popad
    je @finish
    mov eax, [edx+$dc]
    call eax
    test al, al
    @finish:
    ret
end;
//--------------------------------------------------------------------------------------------------------------------

function Init:boolean;
begin
  result:=false;
  //������ ��� (���������� �����) � ������ ���������
  jump_addr:=xrGame_addr+$2D33B9;
  if not WriteJump(jump_addr, cardinal(@GrenadeLauncherBugFix), 5, true) then exit;
  jump_addr:=xrGame_addr+$2D332D;
  if not WriteJump(jump_addr, cardinal(@GrenadeLauncherBugFix), 5, true) then exit;
  jump_addr:=xrGame_addr+$2D3271;
  if not WriteJump(jump_addr, cardinal(@GrenadeAimBugFix), 5, true) then exit;
  //������ ������� ���� � ��������������
  jump_addr:=xrGame_addr+$2D0F2C;
  if not WriteJump(jump_addr, cardinal(@JammedBugFix), 7, true) then exit;

  //�� ����� �������������� ��� ������������ ��������.
  jump_addr:=xrGame_addr+$2CE821;
  if not WriteJump(jump_addr, cardinal(@ReloadAnimPlayingPatch), 12, true) then exit;

  //���������� � �������������� �� �������� � �������
  jump_addr:=xrGame_addr+$2D1545;
  if not WriteJump(jump_addr, cardinal(@SwitchAnimPlayingPatch), 10, true) then exit;
  jump_addr:=xrGame_addr+$2D3DC4;
  if not WriteJump(jump_addr, cardinal(@SwitchAnimPlayingPatch2), 6, true) then exit;

  //��� �����
  jump_addr:=xrGame_addr+$2F9ED1;
  if not WriteJump(jump_addr, cardinal(@BoreAnimLockFix), 5, true) then exit;

  //��� ��������
  jump_addr:=xrGame_addr+$2D02FF;
  if not WriteJump(jump_addr, cardinal(@HideAnimLockFix), 8, true) then exit;

  //��� �������� � ���������
  jump_addr:=xrGame_addr+$2D3ABE;
  if not WriteJump(jump_addr, cardinal(@ShootGLAnimLockFix), 7, true) then exit;

  //��� ������������
  jump_addr:=xrGame_addr+$2BECE4;
  if not WriteJump(jump_addr, cardinal(@AimAnimLockFix), 7, true) then exit;

  //��� ���������
  jump_addr:=xrGame_addr+$2CFE69;
  if not WriteJump(jump_addr, cardinal(@ShootAnimLockFix), 6, true) then exit;

  //��� �������
  jump_addr:=xrGame_addr+$26AF60;
  if not WriteJump(jump_addr, cardinal(@SprintAnimLockFix), 10, true) then exit;

  //������ ���������� ����� ���������� ����
  jump_addr:=xrGame_addr+$2727B3;
  if not WriteJump(jump_addr, cardinal(@IdleSlowFixPatch), 7, true) then exit;


  //������ ����������� ����������� ��������
  jump_addr:=xrGame_addr+$2F9FBC; //anm_idle
  if not WriteJump(jump_addr, cardinal(@anm_idle_sub_patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2D33A5; //anm_idle_w_gl
  if not WriteJump(jump_addr, cardinal(@anm_idle_sub_patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2D3319;//anm_idle_g
  if not WriteJump(jump_addr, cardinal(@anm_idle_sub_patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2c5376;//anm_idle_empty
  if not WriteJump(jump_addr, cardinal(@anm_idle_sub_patch), 5, true) then exit;

  jump_addr:=xrGame_addr+$2F9B44;//anm_idle_sprint
  if not WriteJump(jump_addr, cardinal(@anm_idle_sub_patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2D33DB; //anm_idle_sprint_w_gl
  if not WriteJump(jump_addr, cardinal(@anm_idle_sub_patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2D334F;//anm_idle_sprint_g
  if not WriteJump(jump_addr, cardinal(@anm_idle_sub_patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2c529c;//anm_idle_sprint_empty
  if not WriteJump(jump_addr, cardinal(@anm_idle_sub_patch), 5, true) then exit;


  jump_addr:=xrGame_addr+$2F9AC4;//anm_idle_moving
  if not WriteJump(jump_addr, cardinal(@anm_idle_sub_patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2D3370;//anm_idle_moving_g
  if not WriteJump(jump_addr, cardinal(@anm_idle_sub_patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2D33FC;//anm_idle_moving_w_gl
  if not WriteJump(jump_addr, cardinal(@anm_idle_sub_patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2C530C;//anm_idle_moving_empty
  if not WriteJump(jump_addr, cardinal(@anm_idle_sub_patch), 5, true) then exit;

  jump_addr:=xrGame_addr+$2CD013;//anm_idle_aim
  if not WriteJump(jump_addr, cardinal(@anm_idle_std_patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2D3278;//anm_idle_w_gl_aim
  if not WriteJump(jump_addr, cardinal(@anm_idle_sub_patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2D325F;//anm_idle_g_aim
  if not WriteJump(jump_addr, cardinal(@anm_idle_sub_patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2C53DC;//anm_idle_aim_empty
  if not WriteJump(jump_addr, cardinal(@anm_idle_std_patch), 5, true) then exit;

  //idles for WP_BM16
  ///////////////////////////////////////////////////////////////////////////////////
  jump_addr:=xrGame_addr+$2E08B7;//anm_idle_0
  if not WriteJump(jump_addr, cardinal(@anm_idle_sub_patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2E088F;//anm_idle_1
  if not WriteJump(jump_addr, cardinal(@anm_idle_sub_patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2E0867;//anm_idle_2
  if not WriteJump(jump_addr, cardinal(@anm_idle_sub_patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2E0679;//anm_idle_moving_0
  if not WriteJump(jump_addr, cardinal(@anm_idle_sub_patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2E0646;//anm_idle_moving_1
  if not WriteJump(jump_addr, cardinal(@anm_idle_sub_patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2E0613;//anm_idle_moving_2
  if not WriteJump(jump_addr, cardinal(@anm_idle_sub_patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2E082D;//anm_idle_aim_0
  if not WriteJump(jump_addr, cardinal(@anm_idle_sub_patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2E0802;//anm_idle_aim_1
  if not WriteJump(jump_addr, cardinal(@anm_idle_sub_patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2E07E2;//anm_idle_aim_2
  if not WriteJump(jump_addr, cardinal(@anm_idle_sub_patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2E0759;//anm_idle_sprint_0
  if not WriteJump(jump_addr, cardinal(@anm_idle_sub_patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2E0726;//anm_idle_sprint_1
  if not WriteJump(jump_addr, cardinal(@anm_idle_sub_patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2E06F3;//anm_idle_sprint_2
  if not WriteJump(jump_addr, cardinal(@anm_idle_sub_patch), 5, true) then exit;
  ///////////////////////////////////////////////////////////////////////////////////

  jump_addr:=xrGame_addr+$2C519D;//anm_show_empty
  if not WriteJump(jump_addr, cardinal(@anm_show_sub_patch), 5, true) then exit;
{  jump_addr:=xrGame_addr+$2C75A5;//anm_show - grenades
  if not WriteJump(jump_addr, cardinal(@anm_show_std_patch), 5, true) then exit;}
  jump_addr:=xrGame_addr+$2CCED2;//anm_show - spas12, rg6
  if not WriteJump(jump_addr, cardinal(@anm_show_std_patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2D176A;//anm_show - assault
  if not WriteJump(jump_addr, cardinal(@anm_show_std_patch), 5, true) then exit;
{  jump_addr:=xrGame_addr+$2E3A2B;//anm_show - artefacts
  if not WriteJump(jump_addr, cardinal(@anm_show_sub_patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2EC9F3;//anm_show - detectors - DON'T USE IT!
  if not WriteJump(jump_addr, cardinal(@anm_show_sub_patch), 5, true) then exit;}
  jump_addr:=xrGame_addr+$2D173E;//anm_show_g
  if not WriteJump(jump_addr, cardinal(@anm_show_std_patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2D1721;//anm_show_w_gl
  if not WriteJump(jump_addr, cardinal(@anm_show_std_patch), 5, true) then exit;
  ///////////////////////////////////////////////////////////////////////////////////
  jump_addr:=xrGame_addr+$2C54FD;//anm_hide_empty
  if not WriteJump(jump_addr, cardinal(@anm_hide_sub_patch), 5, true) then exit;
{  jump_addr:=xrGame_addr+$2C7624;//anm_hide - grenades
  if not WriteJump(jump_addr, cardinal(@anm_hide_std_patch), 5, true) then exit;}
  jump_addr:=xrGame_addr+$2CCF42;//anm_hide - spas12, rg6
  if not WriteJump(jump_addr, cardinal(@anm_hide_std_patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2D182A;//anm_hide - assault
  if not WriteJump(jump_addr, cardinal(@anm_hide_std_patch), 5, true) then exit;
{  jump_addr:=xrGame_addr+$2E3A6D;//anm_hide - artefacts
  if not WriteJump(jump_addr, cardinal(@anm_hide_sub_patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2EC951;//anm_hide - detectors - DON'T USE IT!
  if not WriteJump(jump_addr, cardinal(@anm_hide_sub_patch), 5, true) then exit;}
  jump_addr:=xrGame_addr+$2D17FE;//anm_hide_g
  if not WriteJump(jump_addr, cardinal(@anm_hide_std_patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2D17E1;//anm_show_w_gl
  if not WriteJump(jump_addr, cardinal(@anm_hide_std_patch), 5, true) then exit;
  //////////////////////////////////////////////////////////////////////////////////
  jump_addr:=xrGame_addr+$2F9BC4;//anm_bore
  if not WriteJump(jump_addr, cardinal(@anm_bore_sub_patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2D1A7B;//anm_bore_g
  if not WriteJump(jump_addr, cardinal(@anm_bore_sub_patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2D1A99;//anm_bore_w_gl
  if not WriteJump(jump_addr, cardinal(@anm_bore_sub_patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2C5227;//anm_bore_empty
  if not WriteJump(jump_addr, cardinal(@anm_bore_edi_patch), 5, true) then exit;
  ////////////////////////////////////////////////////////////////////////////////
  jump_addr:=xrGame_addr+$2D1A05;//anm_switch
  if not WriteJump(jump_addr, cardinal(@anm_switch_sub_patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2D19D0;//anm_switch_g
  if not WriteJump(jump_addr, cardinal(@anm_switch_sub_patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2D191C;//anm_shoot_g
  if not WriteJump(jump_addr, cardinal(@anm_shoot_g_std_patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2D1E3D;//anm_shoot_g
  if not WriteJump(jump_addr, cardinal(@anm_reload_g_std_patch), 5, true) then exit;
  ////////////////////////////////////////////////////////////////////////////////
  jump_addr:=xrGame_addr+$2C5571;//anm_shots, anm_shots_l - pistols
  if not WriteJump(jump_addr, cardinal(@anm_shots_std_patch), 14, true) then exit;
  jump_addr:=xrGame_addr+$2CD0B2;//anm_shots - other
  if not WriteJump(jump_addr, cardinal(@anm_shots_std_patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2D196C;//anm_shots_w_gl
  if not WriteJump(jump_addr, cardinal(@anm_shots_std_patch), 5, true) then exit;
  ////////////////////////////////////////////////////////////////////////////////
  jump_addr:=xrGame_addr+$2DE462;//anm_open
  if not WriteJump(jump_addr, cardinal(@anm_open_std_patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2DE542;//anm_close
  if not WriteJump(jump_addr, cardinal(@anm_close_std_patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2DE4D2;//anm_add_cartridge
  if not WriteJump(jump_addr, cardinal(@anm_add_cartridge_std_patch), 5, true) then exit;

  jump_addr:=xrGame_addr+$2CCFB2;//anm_reload
  if not WriteJump(jump_addr, cardinal(@anm_reload_std_patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2D18AB;//anm_reload_w_gl
  if not WriteJump(jump_addr, cardinal(@anm_reload_std_patch), 5, true) then exit;

  jump_addr:=xrGame_addr+$2E057C;//anm_reload_1 - BM16
  if not WriteJump(jump_addr, cardinal(@anm_reload_std_patch), 5, true) then exit;

  jump_addr:=xrGame_addr+$2E0547;//anm_reload_2 - BM16
  if not WriteJump(jump_addr, cardinal(@anm_reload_std_patch), 5, true) then exit;

  jump_addr:=xrGame_addr+$2C5451;//reload - pistols
  if not WriteJump(jump_addr, cardinal(@anm_reload_std_patch), 14, true) then exit;
  result:=true;
end;


end.