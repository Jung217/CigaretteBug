import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/cigarette_brand.dart';

class BrandDatabase {
  static final BrandDatabase _instance = BrandDatabase._();
  factory BrandDatabase() => _instance;
  BrandDatabase._();

  List<CigaretteBrand> _brands = [];
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    final jsonStr = await rootBundle.loadString('assets/brand_data.json');
    final list = json.decode(jsonStr) as List;
    _brands = list.map((e) => CigaretteBrand.fromJson(e as Map<String, dynamic>)).toList();
    _loaded = true;
  }

  List<CigaretteBrand> get allBrands => _brands;

  CigaretteBrand? findByBarcode(String barcode) {
    try {
      return _brands.firstWhere((b) => b.barcode == barcode);
    } catch (_) {
      return null;
    }
  }

  List<CigaretteBrand> search(String query) {
    final q = query.toLowerCase();
    return _brands.where((b) =>
      b.name.toLowerCase().contains(q) ||
      b.nameZH.contains(q) ||
      b.manufacturer.toLowerCase().contains(q)
    ).toList();
  }
}
