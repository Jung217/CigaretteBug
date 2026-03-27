enum PackType { standard, slim, soft, heatStick }

enum ProductType { traditional, heatStick, heatDevice }

class CigaretteBrand {
  final String barcode;
  final String name;
  final String nameZH;
  final String manufacturer;
  final double tar;
  final double nicotine;
  final int packPrice;
  final int packSize;
  final PackType packType;
  final ProductType productType;
  final String? pairedDeviceId;
  final int colorValue; // fallback color for 2.5D box

  const CigaretteBrand({
    required this.barcode,
    required this.name,
    required this.nameZH,
    required this.manufacturer,
    required this.tar,
    required this.nicotine,
    required this.packPrice,
    required this.packSize,
    required this.packType,
    required this.productType,
    this.pairedDeviceId,
    required this.colorValue,
  });

  factory CigaretteBrand.fromJson(Map<String, dynamic> json) {
    return CigaretteBrand(
      barcode: json['barcode'] as String,
      name: json['name'] as String,
      nameZH: json['nameZH'] as String,
      manufacturer: json['manufacturer'] as String,
      tar: (json['tar'] as num).toDouble(),
      nicotine: (json['nicotine'] as num).toDouble(),
      packPrice: json['packPrice'] as int,
      packSize: json['packSize'] as int,
      packType: PackType.values.byName(json['packType'] as String),
      productType: ProductType.values.byName(json['productType'] as String),
      pairedDeviceId: json['pairedDeviceId'] as String?,
      colorValue: json['colorValue'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
    'barcode': barcode,
    'name': name,
    'nameZH': nameZH,
    'manufacturer': manufacturer,
    'tar': tar,
    'nicotine': nicotine,
    'packPrice': packPrice,
    'packSize': packSize,
    'packType': packType.name,
    'productType': productType.name,
    'colorValue': colorValue,
    'pairedDeviceId': pairedDeviceId,
  };
}
