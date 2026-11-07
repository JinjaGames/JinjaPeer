import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/codes.dart';
import '../../core/format.dart';
import '../../services/peer_session.dart';
import '../theme.dart';
import '../widgets/chrome.dart';
import '../widgets/dialogs.dart';
import '../widgets/glass.dart';
import '../widgets/liquid_background.dart';

enum ConnectMode { invite, join }

Future<void> showConnectDialog(BuildContext context, {ConnectMode mode = ConnectMode.invite, String? initialCode}) {
  return showGlassDialog(
    context,
    maxWidth: 600,
    dismissible: false,
    child: ConnectDialog(mode: mode, initialCode: initialCode),
  );
}

class ConnectDialog extends StatefulWidget {
  const ConnectDialog({super.key, required this.mode, this.initialCode});
  final ConnectMode mode;
  final String? initialCode;

  @override
  State<ConnectDialog> createState() => _ConnectDialogState();
}

class _ConnectDialogState extends State<ConnectDialog> {
  late ConnectMode _mode = widget.mode;
  PeerSession? _session;
  bool _busy = false;

  // invite form
  bool _usePassword = false;
  final _pw = TextEditingController();
  bool _pwVisible = false;

  // join form
  late final _invite = TextEditingController(text: widget.initialCode ?? '');
  final _joinPw = TextEditingController();
  ConnectionCode? _parsed;
  String? _parseError;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    if (widget.initialCode != null) _parse();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _session?.removeListener(_onSession);
    super.dispose();
  }

  void _onSession() {
    if (!mounted) return;
    setState(() {});
    if (_session?.state == SessionState.connected) {
      Future<void>.delayed(const Duration(milliseconds: 1400), () {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
  }

  void _adopt(PeerSession s) {
    _session?.removeListener(_onSession);
    _session = s;
    s.addListener(_onSession);
  }

  Future<void> _createInvite() async {
    if (_usePassword && _pw.text.length < 4) {
      setState(() {});
      return;
    }
    setState(() => _busy = true);
    final s = await context.appRead.createInvite(password: _usePassword ? _pw.text : null);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _adopt(s);
    });
  }

  void _parseLater() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _parse);
  }

  Future<void> _parse() async {
    final text = _invite.text;
    if (text.trim().isEmpty) {
      setState(() {
        _parsed = null;
        _parseError = null;
      });
      return;
    }
    try {
      final c = await ConnectionCode.parse(text, expect: CodeKind.invite);
      if (!mounted || text != _invite.text) return;
      setState(() {
        _parsed = c;
        _parseError = null;
      });
    } on CodeException catch (e) {
      if (!mounted || text != _invite.text) return;
      setState(() {
        _parsed = null;
        _parseError = e.message;
      });
    }
  }

  Future<void> _join() async {
    final code = _parsed;
    if (code == null) return;
    if (code.passwordRequired && _joinPw.text.isEmpty) return;
    setState(() => _busy = true);
    final s = await context.appRead.joinWithCode(code,
        password: code.passwordRequired ? _joinPw.text : null);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _adopt(s);
    });
  }

  Future<void> _pasteInvite() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null) return;
    _invite.text = data!.text!.trim();
    await _parse();
  }

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    final started = _session != null;
    return Shortcuts(
      shortcuts: const {SingleActivator(LogicalKeyboardKey.escape): DismissIntent()},
      child: Actions(
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(onInvoke: (_) => Navigator.of(context).maybePop()),
        },
        child: Focus(
          autofocus: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DialogHeader(
                icon: _mode == ConnectMode.invite ? Icons.add_link_rounded : Icons.login_rounded,
                title: 'Yeni bağlantı',
                subtitle: 'Sunucu yok: iki cihaz, kodları değiş tokuş ederek doğrudan ve şifreli bağlanır.',
              ),
              const SizedBox(height: S.lg),
              if (!started)
                Center(
                  child: Segmented<ConnectMode>(
                    value: _mode,
                    items: const [
                      (ConnectMode.invite, 'Davet et', Icons.qr_code_2_rounded),
                      (ConnectMode.join, 'Koda katıl', Icons.input_rounded),
                    ],
                    onChanged: (m) => setState(() => _mode = m),
                  ),
                ),
              if (!started) const SizedBox(height: S.lg),
              Flexible(
                child: SingleChildScrollView(
                  child: SmoothSize(
                    duration: Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: SmoothSwitcher(
                      duration: Duration(milliseconds: 240),
                      child: started
                          ? PendingSessionPanel(key: ValueKey(_session!.id), session: _session!)
                          : _mode == ConnectMode.invite
                              ? _inviteForm(jp)
                              : _joinForm(jp),
                    ),
                  ),
                ),
              ),
              if (started && _session!.state.isOver) ...[
                const SizedBox(height: S.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    JButton(
                      label: 'Baştan başla',
                      icon: Icons.refresh_rounded,
                      kind: BtnKind.secondary,
                      onPressed: () {
                        context.appRead.removeSession(_session!);
                        setState(() {
                          _session?.removeListener(_onSession);
                          _session = null;
                        });
                      },
                    ),
                  ],
                ),
              ],
              if (started && !_session!.state.isOver && !_session!.state.isLive) ...[
                const SizedBox(height: S.md),
                Text(
                  'Pencereyi kapatabilirsin; bu bağlantı "Bağlantılar" sayfasında beklemeye devam eder.',
                  style: TextStyle(color: jp.textFaint, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _inviteForm(JP jp) {
    final pwError = _usePassword && _pw.text.isNotEmpty && _pw.text.length < 4;
    return Column(
      key: const ValueKey('invite'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _HowItWorks(steps: [
          ('Davet kodu oluştur', 'Kodu karşı tarafa istediğin yoldan gönder (WhatsApp, Discord, e-posta…).'),
          ('Yanıt kodunu al', 'Karşı taraf kodu yapıştırınca sana bir yanıt kodu verir.'),
          ('Yapıştır ve bağlan', 'Yanıtı buraya yapıştırdığın an doğrudan şifreli bağlantı kurulur.'),
        ]),
        const SizedBox(height: S.lg),
        _OptionRow(
          icon: Icons.password_rounded,
          title: 'Ek bağlantı şifresi',
          subtitle: 'İsteğe bağlı. Kod yanlış ellere geçse bile şifreyi bilmeyen bağlanamaz.',
          value: _usePassword,
          onChanged: (v) => setState(() => _usePassword = v),
        ),
        SmoothSize(
          duration: Duration(milliseconds: 200),
          child: _usePassword
              ? Padding(
                  padding: const EdgeInsets.only(top: S.md),
                  child: TextField(
                    controller: _pw,
                    obscureText: !_pwVisible,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _createInvite(),
                    decoration: InputDecoration(
                      labelText: 'Şifre (en az 4 karakter)',
                      helperText: 'Şifreyi kodla aynı kanaldan göndermemen önerilir (ör. sesli söyle).',
                      errorText: pwError ? 'En az 4 karakter olmalı' : null,
                      prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
                      suffixIcon: IconButton(
                        tooltip: _pwVisible ? 'Gizle' : 'Göster',
                        icon: Icon(_pwVisible ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 18),
                        onPressed: () => setState(() => _pwVisible = !_pwVisible),
                      ),
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        const SizedBox(height: S.xl),
        JButton(
          label: 'Davet kodu oluştur',
          icon: Icons.auto_awesome_rounded,
          loading: _busy,
          expand: true,
          onPressed: (_usePassword && _pw.text.length < 4) ? null : _createInvite,
        ),
      ],
    );
  }

  Widget _joinForm(JP jp) {
    final c = _parsed;
    final known = c == null ? null : context.app.contactForInvite(c);
    return Column(
      key: const ValueKey('join'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Karşı tarafın gönderdiği davet kodunu yapıştır', style: context.tt.titleSmall),
        const SizedBox(height: S.sm),
        TextField(
          controller: _invite,
          minLines: 3,
          maxLines: 5,
          autofocus: true,
          onChanged: (_) => _parseLater(),
          style: const TextStyle(fontFamily: kMono, fontSize: 12),
          decoration: InputDecoration(
            hintText: 'JP1I-…',
            errorText: _parseError,
            errorMaxLines: 3,
            suffixIcon: Padding(
              padding: const EdgeInsets.all(6),
              child: JIconButton(
                icon: Icons.content_paste_rounded,
                tooltip: 'Panodan yapıştır',
                onPressed: _pasteInvite,
              ),
            ),
          ),
        ),
        SmoothSize(
          duration: Duration(milliseconds: 220),
          child: c == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: S.md),
                  child: Glass(
                    padding: const EdgeInsets.all(S.md),
                    radius: R.md,
                    tint: jp.success,
                    shadow: false,
                    child: Row(
                      children: [
                        Avatar(name: known?.name ?? c.name, seed: known?.colorSeed ?? c.name.hashCode, size: 38),
                        const SizedBox(width: S.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${known?.name ?? c.name} seni davet ediyor', style: context.tt.titleSmall),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  Pill('İmza doğrulandı', icon: Icons.verified_rounded, color: jp.success),
                                  if (known != null)
                                    Pill('Kayıtlı kişi', icon: Icons.person_rounded, color: jp.accent),
                                  Pill('${formatDuration(c.remaining)} geçerli', icon: Icons.timer_outlined),
                                  if (c.passwordRequired)
                                    Pill('Şifre gerekli', icon: Icons.lock_rounded, color: jp.warning),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
        if (c != null && c.passwordRequired) ...[
          const SizedBox(height: S.md),
          TextField(
            controller: _joinPw,
            obscureText: true,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _join(),
            decoration: const InputDecoration(
              labelText: 'Bağlantı şifresi',
              helperText: 'Davet eden kişinin belirlediği şifre',
              prefixIcon: Icon(Icons.lock_outline_rounded, size: 18),
            ),
          ),
        ],
        const SizedBox(height: S.xl),
        JButton(
          label: 'Katıl ve yanıt kodu oluştur',
          icon: Icons.arrow_forward_rounded,
          loading: _busy,
          expand: true,
          onPressed: c == null || (c.passwordRequired && _joinPw.text.isEmpty) ? null : _join,
        ),
      ],
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    return GlassTile(
      padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.md),
      radius: R.md,
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          Icon(icon, size: 20, color: jp.textMuted),
          const SizedBox(width: S.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.tt.titleSmall),
                Text(subtitle, style: TextStyle(color: jp.textMuted, fontSize: 12)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks({required this.steps});
  final List<(String, String)> steps;

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: S.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: jp.accentGradient,
                  ),
                  child: Text('${i + 1}',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: S.md),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '${steps[i].$1}  ', style: context.tt.titleSmall),
                      TextSpan(text: steps[i].$2, style: TextStyle(color: jp.textMuted, fontSize: 12.5)),
                    ]),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Everything about a session that is not yet connected (or just connected):
/// the code to share, the answer field, progress and errors.
class PendingSessionPanel extends StatefulWidget {
  const PendingSessionPanel({super.key, required this.session});
  final PeerSession session;

  @override
  State<PendingSessionPanel> createState() => _PendingSessionPanelState();
}

class _PendingSessionPanelState extends State<PendingSessionPanel> {
  final _answer = TextEditingController();
  String? _answerError;
  bool _applying = false;
  bool _showQr = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _apply([String? text]) async {
    final value = text ?? _answer.text;
    if (value.trim().isEmpty) return;
    setState(() {
      _applying = true;
      _answerError = null;
    });
    try {
      final code = await ConnectionCode.parse(value, expect: CodeKind.answer);
      await widget.session.applyAnswer(code);
    } on CodeException catch (e) {
      _answerError = e.message;
    } catch (e) {
      _answerError = 'Yanıt uygulanamadı: $e';
    }
    if (mounted) setState(() => _applying = false);
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null) return;
    _answer.text = data!.text!.trim();
    await _apply();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final jp = context.jp;
    final s = widget.session;
    switch (s.state) {
      case SessionState.preparing:
        return _Progress(
          title: s.role == SessionRole.inviter ? 'Davet kodu hazırlanıyor' : 'Yanıt kodu hazırlanıyor',
          message: 'Bu cihazın ağ adresleri toplanıyor ve tek kullanımlık şifreleme anahtarları üretiliyor…',
        );
      case SessionState.failed:
      case SessionState.closed:
        return _ResultCard(
          ok: false,
          title: s.state == SessionState.failed ? 'Bağlantı kurulamadı' : 'Bağlantı kapandı',
          message: s.error ?? 'Bağlantı sona erdi.',
        );
      case SessionState.connecting:
      case SessionState.securing:
        return _ConnectingSteps(state: s.state);
      case SessionState.connected:
        return _ResultCard(
          ok: true,
          title: '${s.displayName} ile bağlandın',
          message: 'Uçtan uca şifreli kanal hazır. Doğrulama kodu: ${s.verificationCode}',
        );
      case SessionState.waitingForAnswer:
      case SessionState.waitingForPeer:
        break;
    }

    final code = s.myCode!;
    final remaining = code.remaining;
    final isInviter = s.role == SessionRole.inviter;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StepHeader(
          n: 1,
          title: isInviter ? 'Bu davet kodunu karşı tarafa gönder' : 'Bu yanıt kodunu davet edene geri gönder',
          trailing: Pill(
            remaining.isNegative ? 'Süresi doldu' : '${formatDuration(remaining)} kaldı',
            icon: Icons.timer_outlined,
            color: remaining.inMinutes < 2 ? jp.warning : null,
          ),
        ),
        const SizedBox(height: S.sm),
        SmoothSwitcher(
          duration: Duration(milliseconds: 220),
          child: _showQr
              ? Center(
                  key: const ValueKey('qr'),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(R.md)),
                    child: QrImageView(
                      data: code.encoded,
                      size: 260,
                      errorCorrectionLevel: QrErrorCorrectLevel.L,
                      errorStateBuilder: (context, _) => const SizedBox(
                        width: 260,
                        height: 80,
                        child: Center(
                          child: Text('Kod QR için çok uzun, kopyala-yapıştır kullan.',
                              style: TextStyle(color: Colors.black54), textAlign: TextAlign.center),
                        ),
                      ),
                    ),
                  ),
                )
              : CodeBlock(
                  key: const ValueKey('code'),
                  code: code.encoded,
                  maxLines: 4,
                  onCopied: () => context.appRead.notify('Kopyalandı', 'Kodu şimdi karşı tarafa yapıştırıp gönder.'),
                ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(top: S.xs),
            child: JButton(
              label: _showQr ? 'Metin olarak göster' : 'QR kod olarak göster',
              icon: _showQr ? Icons.notes_rounded : Icons.qr_code_rounded,
              kind: BtnKind.ghost,
              dense: true,
              onPressed: () => setState(() => _showQr = !_showQr),
            ),
          ),
        ),
        const SizedBox(height: S.md),
        if (isInviter) ...[
          _StepHeader(n: 2, title: 'Karşı tarafın yanıt kodunu yapıştır'),
          const SizedBox(height: S.sm),
          TextField(
            controller: _answer,
            minLines: 2,
            maxLines: 4,
            style: const TextStyle(fontFamily: kMono, fontSize: 12),
            onChanged: (v) {
              if (_answerError != null) setState(() => _answerError = null);
              // Auto-connect as soon as a complete answer code is pasted.
              if (ConnectionCode.sniff(v) == CodeKind.answer && v.trim().length > 200) _apply(v);
            },
            decoration: InputDecoration(
              hintText: 'JP1A-…',
              errorText: _answerError,
              errorMaxLines: 3,
              suffixIcon: Padding(
                padding: const EdgeInsets.all(6),
                child: JIconButton(
                  icon: Icons.content_paste_rounded,
                  tooltip: 'Panodan yapıştır ve bağlan',
                  onPressed: _paste,
                ),
              ),
            ),
          ),
          const SizedBox(height: S.md),
          JButton(
            label: 'Bağlan',
            icon: Icons.link_rounded,
            loading: _applying,
            expand: true,
            onPressed: _apply,
          ),
        ] else
          Glass(
            padding: const EdgeInsets.all(S.md),
            radius: R.md,
            shadow: false,
            child: Row(
              children: [
                PulseDot(color: jp.accent),
                const SizedBox(width: S.md),
                Expanded(
                  child: Text(
                    '${s.displayName} bu kodu yapıştırdığında bağlantı kendiliğinden kurulacak. Uygulamayı açık tut.',
                    style: TextStyle(color: jp.textMuted, fontSize: 12.5, height: 1.45),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.n, required this.title, this.trailing});
  final int n;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, gradient: jp.accentGradient),
          child: Text('$n', style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: S.sm),
        Expanded(child: Text(title, style: context.tt.titleSmall)),
        ?trailing,
      ],
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.title, required this.message});
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.lg),
      child: Column(
        children: [
          const LiquidProgress(value: 0, indeterminate: true, height: 6),
          const SizedBox(height: S.lg),
          Text(title, style: context.tt.titleMedium),
          const SizedBox(height: S.xs),
          Text(message, textAlign: TextAlign.center, style: TextStyle(color: jp.textMuted, fontSize: 12.5)),
        ],
      ),
    );
  }
}

class _ConnectingSteps extends StatelessWidget {
  const _ConnectingSteps({required this.state});
  final SessionState state;

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    final steps = [
      ('Doğrudan ağ yolu aranıyor', SessionState.connecting),
      ('Şifreli kanal kuruluyor (DTLS + ChaCha20)', SessionState.securing),
      ('Anahtarlar karşılıklı doğrulanıyor', SessionState.connected),
    ];
    final current = state.index;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LiquidProgress(value: 0, indeterminate: true, height: 6),
          const SizedBox(height: S.lg),
          for (final (label, st) in steps)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: st.index <= current
                        ? Icon(Icons.check_circle_rounded, size: 18, color: jp.success)
                        : (st.index == current + 1
                            ? PulseDot(color: jp.accent, size: 7)
                            : Icon(Icons.radio_button_unchecked_rounded, size: 18, color: jp.textFaint)),
                  ),
                  const SizedBox(width: S.sm),
                  Text(label,
                      style: TextStyle(
                        color: st.index <= current + 1 ? jp.text : jp.textFaint,
                        fontSize: 13,
                      )),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.ok, required this.title, required this.message});
  final bool ok;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final jp = context.jp;
    final c = ok ? jp.success : jp.danger;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.md),
      child: Column(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.6, end: 1),
            duration: Duration(milliseconds: 500),
            curve: Curves.elasticOut,
            builder: (context, v, child) => Transform.scale(scale: v, child: child),
            child: IconOrb(
              ok ? Icons.check_rounded : Icons.link_off_rounded,
              size: 64,
              colors: [c, c],
            ),
          ),
          const SizedBox(height: S.lg),
          Text(title, style: context.tt.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: S.xs),
          Text(message,
              textAlign: TextAlign.center, style: TextStyle(color: jp.textMuted, fontSize: 13, height: 1.5)),
        ],
      ),
    );
  }
}
