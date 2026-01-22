import 'dart:math';

//Slug generation utility

String generateSlug(int length) {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final rand = Random();
  return List.generate(
    length,
    (index) => chars[(rand.nextInt(chars.length) + index) % chars.length],
  ).join();
}
