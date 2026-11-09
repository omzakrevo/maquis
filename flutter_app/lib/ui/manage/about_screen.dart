import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

const appVersion = '0.9.0';

/// Version, logo et crédits des photos embarquées (exigés par les licences CC BY / BY-SA).
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  Future<List<Map<String, dynamic>>> _credits() async => (jsonDecode(await rootBundle.loadString('assets/products/credits.json')) as List).cast<Map<String, dynamic>>();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: gradientAppBar(context, title: const Text('À propos')),
    body: PatternBackground(
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _credits(),
        builder: (context, snap) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SizedBox(height: 8),
            const BrandMark(size: 110),
            const SizedBox(height: 6),
            const Text('Version $appVersion · caisse pour maquis, restaurants, boutiques et pharmacies', textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(
              'OMZAKREVO INFORMATIQUE — « Toujours une solution ! »',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.brick),
            ),
            const SizedBox(height: 20),
            const Text('Crédits des photos produits', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            const Text('Photos libres (Wikimedia Commons, Flickr) recadrées. Les marques visibles appartiennent à leurs propriétaires.'),
            const SizedBox(height: 8),
            for (final c in snap.data ?? const <Map<String, dynamic>>[])
              Card(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.asset(c['file'] as String, width: 52, height: 52, fit: BoxFit.cover),
                  ),
                  title: Text(c['product'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: SelectableText('« ${c['title']} » par ${c['author']} — ${c['license']}\n${c['source']}', style: const TextStyle(fontSize: 12)),
                  isThreeLine: true,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
