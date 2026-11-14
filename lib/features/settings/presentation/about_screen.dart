import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../shared/widgets/common.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('About Bondbell')),
      body: PageList(
        maxWidth: 680,
        children: <Widget>[
          Text('How Bondbell works', style: t.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'You save your bond numbers on this ${deviceNoun(context)}. When '
            'you ask it to check, Bondbell downloads NS&I\'s public list of '
            'winning numbers directly from nsandi.com, compares it with your '
            'numbers on the ${deviceNoun(context)}, keeps only the matches, '
            'and deletes the download.\n\n'
            'Nothing you enter is sent anywhere. There\'s no account, no '
            'server of ours in the middle, no analytics and no ads.',
            style: t.textTheme.bodyLarge,
          ),
          const SizedBox(height: 20),
          const SectionCard(
            title: 'Independent app',
            icon: Icons.info_outline,
            child: Text(AppConstants.independenceNotice),
          ),
          const SizedBox(height: 16),
          const SectionCard(
            title: 'Results',
            icon: Icons.verified_user_outlined,
            child: Text(
              '${AppConstants.confirmWithNsi} Lists are NS&I\'s, used for '
              'your personal checking under the terms of their website.',
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Contact',
            icon: Icons.mail_outline,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Questions or problems: ${AppConstants.supportEmail}',
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => openUrl(context, AppConstants.supportUrl),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('bondbell.froggyeye.com'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '${AppConstants.appName} ${AppConstants.appVersionLabel} · '
            '${AppConstants.copyright}',
            style: t.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
