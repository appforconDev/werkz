import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../build_info.dart';
import 'theme.dart';
import 'pairing_screen.dart';

// Pre-pairing onboarding (task 11 A): the app must NOT open straight into the
// camera. "Reporting for duty" — what Werkz is, then numbered 1955-toned steps.
// The camera opens only when the user taps SCAN THE PAIRING REQUISITION.
class OnboardScreen extends StatelessWidget {
  const OnboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Werkz.cream,
      // Task 26 C: pairing where the user is — the primary action is PINNED, not
      // buried below the fold of the onboarding scroll. Opens the QR scanner
      // directly (same route as the in-flow button).
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: FilledButton(
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PairingScreen()),
            ),
            child: const Text('PAIR WORKSHOP',
                style: TextStyle(fontFamily: Werkz.mono, letterSpacing: 2, fontWeight: FontWeight.w900)),
          ),
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('WERKZ INDUSTRIES',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: Werkz.mono, fontWeight: FontWeight.w900, fontSize: 22, letterSpacing: 4)),
              const Text('REPORTING FOR DUTY',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: Werkz.mono, fontSize: 11, color: Werkz.gunmetal, letterSpacing: 3)),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Werkz.manila, border: Border.all(color: Werkz.gunmetal, width: 2)),
                child: const Text(
                  'Your coding agents become workers in a workshop you run from '
                  'your phone. Permission prompts arrive as requisitions you stamp '
                  'with a swipe.',
                  style: TextStyle(fontFamily: Werkz.mono, fontSize: 13, height: 1.5, color: Werkz.machine),
                ),
              ),
              const SizedBox(height: 24),
              const Text('— TO OPEN THE WORKSHOP —',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: Werkz.mono, fontSize: 10, letterSpacing: 2, color: Werkz.gunmetal)),
              const SizedBox(height: 16),
              const _Step(
                n: 1,
                child: _RunCommand(),
              ),
              const _Step(
                n: 2,
                child: Text('A pairing QR appears in your terminal. Scan it with the button below.',
                    style: TextStyle(fontFamily: Werkz.mono, fontSize: 13, height: 1.4)),
              ),
              const _Step(
                n: 3,
                child: Text('Restart your Claude Code session after installing — sessions '
                    'started before you ran the command do not see the hook.',
                    style: TextStyle(fontFamily: Werkz.mono, fontSize: 13, height: 1.4)),
              ),
              const _Step(
                n: 4,
                child: Text('Run Claude Code in DEFAULT permission mode. Decisions only reach '
                    'your phone when Claude asks permission. If you enable acceptEdits / '
                    'auto / bypass, the workshop is bypassed and the app will warn you.',
                    style: TextStyle(fontFamily: Werkz.mono, fontSize: 13, height: 1.4)),
              ),
              const SizedBox(height: 20),
              // Always-on honesty (task 14 A): the workshop runs on the user's
              // machine, not our servers. State it plainly — no apology.
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Werkz.manila, border: Border.all(color: Werkz.gunmetal, width: 2)),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.desktop_windows, size: 16, color: Werkz.machine),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text('THE WORKSHOP LIVES ON YOUR COMPUTER',
                            style: TextStyle(fontFamily: Werkz.mono, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1, color: Werkz.machine)),
                      ),
                    ]),
                    SizedBox(height: 8),
                    Text(
                      'Werkz runs where your code does — on your machine, not our '
                      'servers. For decisions and dispatches while you are away from '
                      'your desk, that machine must be on and awake.',
                      style: TextStyle(fontFamily: Werkz.mono, fontSize: 12, height: 1.5, color: Werkz.machine),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'On macOS, the workshop holds the machine awake while it is '
                      'open (closing the lid still sleeps it unless it is plugged in). '
                      'Hosting it for you — Cloud Workshop — is a planned tier.',
                      style: TextStyle(fontFamily: Werkz.mono, fontSize: 11, height: 1.5, color: Werkz.gunmetal),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Werkz runs in your existing project environment — if claude can '
                      'push or deploy from your terminal, your workers can too. Werkz '
                      'never stores your credentials.',
                      style: TextStyle(fontFamily: Werkz.mono, fontSize: 11, height: 1.5, color: Werkz.gunmetal),
                    ),
                  ],
                ),
              ),
              // Task 34 B: the inline "SCAN THE PAIRING REQUISITION" button was
              // removed — it duplicated the pinned PAIR WORKSHOP bottom bar
              // (scrolling to the bottom showed two identical actions). The bar
              // is Scaffold.bottomNavigationBar (its own region, not an overlay),
              // so it can't hide this last line.
              const SizedBox(height: 8),
            ],
          ),
            ),
            // Build stamp, tiny in the corner (task 17 B) — every device report
            // starts from a known build.
            Positioned(
              right: 6,
              bottom: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                color: Werkz.cream.withValues(alpha: 0.85),
                child: const Text(werkzBuildStamp,
                    style: TextStyle(fontFamily: Werkz.mono, fontSize: 8, color: Werkz.steel)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int n;
  final Widget child;
  const _Step({required this.n, required this.child});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26, height: 26, alignment: Alignment.center,
            decoration: const BoxDecoration(color: Werkz.machine, shape: BoxShape.circle),
            child: Text('$n', style: const TextStyle(fontFamily: Werkz.mono, color: Werkz.cream, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          const SizedBox(width: 12),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _RunCommand extends StatelessWidget {
  const _RunCommand();
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('On your computer, in your project folder, run:',
            style: TextStyle(fontFamily: Werkz.mono, fontSize: 13, height: 1.4)),
        const SizedBox(height: 6),
        InkWell(
          onTap: () async {
            await Clipboard.setData(const ClipboardData(text: 'npx werkz'));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied: npx werkz'), duration: Duration(seconds: 1)),
              );
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: Werkz.oil, border: Border.all(color: Werkz.gunmetal)),
            child: const Row(
              children: [
                Expanded(child: Text('npx werkz',
                    style: TextStyle(fontFamily: Werkz.mono, fontSize: 14, color: Werkz.approvalGreen))),
                Icon(Icons.copy, size: 14, color: Werkz.steel),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Text('requires Node 22+ and Claude Code',
            style: TextStyle(fontFamily: Werkz.mono, fontSize: 10, color: Werkz.steel)),
      ],
    );
  }
}
