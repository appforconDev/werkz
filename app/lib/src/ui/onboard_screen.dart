import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      body: SafeArea(
        child: SingleChildScrollView(
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
              const SizedBox(height: 24),
              FilledButton(
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PairingScreen()),
                ),
                child: const Text('SCAN THE PAIRING REQUISITION',
                    style: TextStyle(fontFamily: Werkz.mono, letterSpacing: 1)),
              ),
            ],
          ),
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
