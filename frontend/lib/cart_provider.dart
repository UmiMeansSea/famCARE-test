import 'package:flutter_riverpod/flutter_riverpod.dart';

class CartItem {
  final int serviceId;
  final String serviceName;
  final int caregiverId;
  final String caregiverName;
  final String date;
  final String startTime;
  final double price;

  CartItem({
    required this.serviceId,
    required this.serviceName,
    required this.caregiverId,
    required this.caregiverName,
    required this.date,
    required this.startTime,
    required this.price,
  });

  Map<String, dynamic> toJson(int patientId) {
    return {
      'patient_id': patientId,
      'service_id': serviceId,
      'caregiver_id': caregiverId,
      'date': date,
      'start_time': startTime,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CartItem &&
          runtimeType == other.runtimeType &&
          serviceId == other.serviceId &&
          caregiverId == other.caregiverId &&
          date == other.date &&
          startTime == other.startTime;

  @override
  int get hashCode =>
      serviceId.hashCode ^ caregiverId.hashCode ^ date.hashCode ^ startTime.hashCode;
}

class CartNotifier extends StateNotifier<List<CartItem>> {
  CartNotifier() : super([]);

  void addItem(CartItem item) {
    // Prevent adding identical slot bookings in frontend
    if (!state.contains(item)) {
      state = [...state, item];
    }
  }

  void removeItem(CartItem item) {
    state = state.where((i) => i != item).toList();
  }

  void clearCart() {
    state = [];
  }

  double get totalPrice {
    return state.fold(0.0, (sum, item) => sum + item.price);
  }
}

final cartProvider = StateNotifierProvider<CartNotifier, List<CartItem>>((ref) {
  return CartNotifier();
});
