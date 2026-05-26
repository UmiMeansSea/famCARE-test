import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'cart_provider.dart';

// Configurable API Base URL
const String baseUrl = "http://localhost:8000";

// Providers for fetching services and slots
final servicesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final response = await http.get(Uri.parse("$baseUrl/services"));
  if (response.statusCode == 200) {
    final List<dynamic> data = json.decode(response.body);
    return data.map((e) => Map<String, dynamic>.from(e)).toList();
  } else {
    throw Exception("Failed to load services");
  }
});

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int selectedPatientId = 1; // Default to John Doe
  Map<String, dynamic>? selectedService;
  DateTime selectedDate = DateTime.now();
  List<Map<String, dynamic>> availableSlots = [];
  bool loadingSlots = false;
  String? checkoutError;
  bool checkoutSuccess = false;

  @override
  void initState() {
    super.initState();
    // Fetch slots after build is done
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(servicesProvider.future).then((services) {
        if (services.isNotEmpty) {
          setState(() {
            selectedService = services.first;
          });
          fetchSlots();
        }
      });
    });
  }

  Future<void> fetchSlots() async {
    if (selectedService == null) return;
    setState(() {
      loadingSlots = true;
      availableSlots = [];
      checkoutError = null;
    });

    final formattedDate = "${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}";
    try {
      final response = await http.get(Uri.parse(
          "$baseUrl/slots/available?service_id=${selectedService!['id']}&date=$formattedDate"));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          availableSlots = data.map((e) => Map<String, dynamic>.from(e)).toList();
        });
      } else {
        setState(() {
          checkoutError = "Failed to load available slots";
        });
      }
    } catch (e) {
      setState(() {
        checkoutError = "Error connecting to backend: $e";
      });
    } finally {
      setState(() {
        loadingSlots = false;
      });
    }
  }

  Future<void> handleCheckout() async {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) return;

    setState(() {
      checkoutError = null;
      checkoutSuccess = false;
    });

    final payload = {
      "items": cart.map((item) => item.toJson(selectedPatientId)).toList(),
    };

    try {
      final response = await http.post(
        Uri.parse("$baseUrl/cart/checkout"),
        headers: {"Content-Type": "application/json"},
        body: json.encode(payload),
      );

      if (response.statusCode == 200) {
        setState(() {
          checkoutSuccess = true;
        });
        ref.read(cartProvider.notifier).clearCart();
      } else {
        final Map<String, dynamic> errorBody = json.decode(response.body);
        setState(() {
          checkoutError = errorBody['detail'] ?? "Booking failed with server error.";
        });
      }
    } catch (e) {
      setState(() {
        checkoutError = "Failed to communicate with backend: $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final servicesAsync = ref.watch(servicesProvider);
    final cart = ref.watch(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text("FamCare Bulk Scheduler"),
        backgroundColor: Colors.teal,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Patient Picker & Service Selection
            const Text(
              "1. Choose Patient & Service",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    decoration: const InputDecoration(labelText: "Patient"),
                    initialValue: selectedPatientId,
                    items: const [
                      DropdownMenuItem(value: 1, child: Text("John Doe")),
                      DropdownMenuItem(value: 2, child: Text("Jane Doe")),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          selectedPatientId = val;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: servicesAsync.when(
                    data: (services) {
                      return DropdownButtonFormField<Map<String, dynamic>>(
                        decoration: const InputDecoration(labelText: "Service"),
                        initialValue: selectedService,
                        items: services.map((s) {
                          return DropdownMenuItem(
                            value: s,
                            child: Text(s['name']),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              selectedService = val;
                            });
                            fetchSlots();
                          }
                        },
                      );
                    },
                    loading: () => const CircularProgressIndicator(),
                    error: (err, stack) => Text("Error loading services: $err"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 2. Date Selection
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Date: ${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}",
                  style: const TextStyle(fontSize: 16),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 30)),
                    );
                    if (picked != null) {
                      setState(() {
                        selectedDate = picked;
                      });
                      fetchSlots();
                    }
                  },
                  child: const Text("Select Date"),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // 3. Slot Picker Grid
            const Text(
              "2. Available Slots (Auto-Assigned Caregivers)",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal),
            ),
            const SizedBox(height: 8),
            if (loadingSlots)
              const Center(child: CircularProgressIndicator())
            else if (availableSlots.isEmpty)
              const Text("No available slots found for this date/service combo.")
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 2.8,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: availableSlots.length,
                itemBuilder: (context, index) {
                  final slot = availableSlots[index];
                  final isAlreadyInCart = cart.any((item) =>
                      item.startTime == slot['start_time'] &&
                      item.caregiverId == slot['caregiver_id'] &&
                      item.date ==
                          "${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}");

                  return Card(
                    color: isAlreadyInCart ? Colors.grey[300] : Colors.teal[50],
                    child: InkWell(
                      onTap: isAlreadyInCart
                          ? null
                          : () {
                              if (selectedService != null) {
                                final formattedDate =
                                    "${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}";
                                cartNotifier.addItem(
                                  CartItem(
                                    serviceId: selectedService!['id'],
                                    serviceName: selectedService!['name'],
                                    caregiverId: slot['caregiver_id'],
                                    caregiverName: slot['caregiver_name'],
                                    date: formattedDate,
                                    startTime: slot['start_time'],
                                    price: selectedService!['price'],
                                  ),
                                );
                              }
                            },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "${slot['start_time']} - ${slot['end_time']}",
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            Text(
                              slot['caregiver_name'],
                              style: const TextStyle(fontSize: 11, color: Colors.black54),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 24),

            // 4. Cart List
            const Divider(),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Your Cart",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal),
                ),
                Text(
                  "Total: \$${cartNotifier.totalPrice.toStringAsFixed(2)}",
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (cart.isEmpty)
              const Text("Cart is empty. Select slots above to populate.")
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: cart.length,
                itemBuilder: (context, index) {
                  final item = cart[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text("${item.serviceName} (\$${item.price.toStringAsFixed(2)})"),
                    subtitle: Text("${item.date} @ ${item.startTime} | Caregiver: ${item.caregiverName}"),
                    trailing: IconButton(
                      icon: const Icon(Icons.remove_circle, color: Colors.red),
                      onPressed: () {
                        cartNotifier.removeItem(item);
                      },
                    ),
                  );
                },
              ),
            const SizedBox(height: 20),

            // 5. Checkout Status and Action
            if (checkoutSuccess)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: Colors.green[100],
                child: const Text(
                  "Success! All bookings have been locked and scheduled successfully.",
                  style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                ),
              ),
            if (checkoutError != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: Colors.red[100],
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Checkout Failed:",
                      style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      checkoutError!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: cart.isEmpty ? null : handleCheckout,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                ),
                child: const Text("Atomically Book All", style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
