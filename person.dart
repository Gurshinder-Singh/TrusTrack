class Person {
  final String id;
  final String name;
  final String subtitle;
  final String initials;

  const Person({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.initials,
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': id,
      'name': name,
      'subtitle': subtitle,
      'initials': initials,
    };
  }

  factory Person.fromMap(Map<String, dynamic> map) {
    return Person(
      id: (map['uid'] ?? map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      subtitle: (map['subtitle'] ?? '').toString(),
      initials: (map['initials'] ?? '').toString(),
    );
  }
}
