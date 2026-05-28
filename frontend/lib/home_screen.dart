import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'cart_provider.dart';

// Configurable API Base URL
const String baseUrl = "https://parabola-estranged-saloon.ngrok-free.dev";

// Providers for fetching services, slots, and bookings
final servicesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final response = await http.get(Uri.parse("$baseUrl/services"));
  if (response.statusCode == 200) {
    final List<dynamic> data = json.decode(response.body);
    return data.map((e) => Map<String, dynamic>.from(e)).toList();
  } else {
    throw Exception("Failed to load services");
  }
});

final patientsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final response = await http.get(Uri.parse("$baseUrl/patients"));
  if (response.statusCode == 200) {
    final List<dynamic> data = json.decode(response.body);
    return data.map((e) => Map<String, dynamic>.from(e)).toList();
  } else {
    throw Exception("Failed to load patients");
  }
});

final bookingHistoryProvider = FutureProvider.family<List<Map<String, dynamic>>, int>((ref, patientId) async {
  final response = await http.get(Uri.parse("$baseUrl/patients/$patientId/bookings"));
  if (response.statusCode == 200) {
    final List<dynamic> data = json.decode(response.body);
    return data.map((e) => Map<String, dynamic>.from(e)).toList();
  } else {
    throw Exception("Failed to load booking history");
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
  bool isCheckingOut = false;

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
      // Clear checkout status when changing criteria to prevent confusing UX
      checkoutError = null;
      checkoutSuccess = false;
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
      isCheckingOut = true;
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
        // Reactive Eviction Trigger: Force immediate reload of booking history
        ref.invalidate(bookingHistoryProvider(selectedPatientId));
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
    } finally {
      setState(() {
        isCheckingOut = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final servicesAsync = ref.watch(servicesProvider);
    final cart = ref.watch(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);
    final historyAsync = ref.watch(bookingHistoryProvider(selectedPatientId));
    final patientsAsync = ref.watch(patientsProvider);

    final formattedDate = "${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}";

    return Scaffold(
      backgroundColor: Colors.grey[50], // Crisp, modern slate grey background
      appBar: AppBar(
        title: const Text(
          "FamCare Bulk Scheduler",
          style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
        ),
        backgroundColor: Colors.teal[700],
        elevation: 0,
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // Main Scrollable Area
          Positioned.fill(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16.0, 20.0, 16.0, 80.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Card 1: Patient & Service Selection
                  Card(
                    color: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.0),
                      side: BorderSide(color: Colors.grey[200]!),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.assignment_ind_outlined, color: Colors.teal[700], size: 22),
                              const SizedBox(width: 8),
                              Text(
                                "1. Choose Patient & Service",
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal[800]),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          patientsAsync.when(
                            data: (patients) {
                              // If current selectedPatientId is not in the loaded patients list, reset to the first one.
                              final hasSelected = patients.any((p) => p['id'] == selectedPatientId);
                              if (!hasSelected && patients.isNotEmpty) {
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  setState(() {
                                    selectedPatientId = patients.first['id'];
                                  });
                                });
                              }
                              return DropdownButtonFormField<int>(
                                decoration: InputDecoration(
                                  labelText: "Select Patient",
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8.0),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                                ),
                                value: selectedPatientId,
                                items: patients.map((p) {
                                  return DropdownMenuItem<int>(
                                    value: p['id'],
                                    child: Text(p['name']),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() {
                                      selectedPatientId = val;
                                      checkoutError = null;
                                      checkoutSuccess = false;
                                    });
                                  }
                                },
                              );
                            },
                            loading: () => const Center(child: CircularProgressIndicator()),
                            error: (err, stack) => Text("Error loading patients: $err"),
                          ),
                          const SizedBox(height: 16),
                          servicesAsync.when(
                            data: (services) {
                              return DropdownButtonFormField<Map<String, dynamic>>(
                                decoration: InputDecoration(
                                  labelText: "Select Service",
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8.0),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                                ),
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
                            loading: () => const Center(child: CircularProgressIndicator()),
                            error: (err, stack) => Text("Error loading services: $err"),
                          ),
                          const SizedBox(height: 16),
                          // Date Selector styled like a form-field card
                          InkWell(
                            onTap: () async {
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
                            borderRadius: BorderRadius.circular(8.0),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey[400]!),
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.calendar_today_outlined, size: 20, color: Colors.grey[600]),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          "Target Date",
                                          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          formattedDate,
                                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.arrow_drop_down, color: Colors.grey[600]),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Card 2: Open Windows
                  Card(
                    color: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.0),
                      side: BorderSide(color: Colors.grey[200]!),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.more_time, color: Colors.teal[700], size: 22),
                              const SizedBox(width: 8),
                              Text(
                                "2. Available Windows",
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal[800]),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (loadingSlots)
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 24.0),
                                child: CircularProgressIndicator(),
                              ),
                            )
                          else if (availableSlots.isEmpty)
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 24.0),
                                child: Text(
                                  "No available slots found for this date/service combo.",
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                            )
                          else
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                childAspectRatio: 2.5,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                              ),
                              itemCount: availableSlots.length,
                              itemBuilder: (context, index) {
                                final slot = availableSlots[index];
                                final isAlreadyInCart = cart.any((item) =>
                                    item.startTime == slot['start_time'] &&
                                    item.caregiverId == slot['caregiver_id'] &&
                                    item.date == formattedDate);

                                return Card(
                                  elevation: 0,
                                  margin: EdgeInsets.zero,
                                  color: isAlreadyInCart ? Colors.grey[200] : Colors.teal[50],
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10.0),
                                    side: BorderSide(
                                      color: isAlreadyInCart ? Colors.grey[300]! : Colors.teal[100]!,
                                    ),
                                  ),
                                  child: InkWell(
                                    onTap: () {
                                      if (selectedService == null) return;
                                      final cartItem = CartItem(
                                        serviceId: selectedService!['id'],
                                        serviceName: selectedService!['name'],
                                        caregiverId: slot['caregiver_id'],
                                        caregiverName: slot['caregiver_name'],
                                        date: formattedDate,
                                        startTime: slot['start_time'],
                                        price: selectedService!['price'],
                                      );
                                      if (isAlreadyInCart) {
                                        cartNotifier.removeItem(cartItem);
                                      } else {
                                        cartNotifier.addItem(cartItem);
                                      }
                                    },
                                    borderRadius: BorderRadius.circular(10.0),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  "${slot['start_time']} - ${slot['end_time']}",
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13,
                                                    color: isAlreadyInCart ? Colors.grey[700] : Colors.teal[900],
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  slot['caregiver_name'],
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: isAlreadyInCart ? Colors.grey[500] : Colors.teal[700],
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                          Icon(
                                            isAlreadyInCart ? Icons.check_circle : Icons.access_time_outlined,
                                            color: isAlreadyInCart ? Colors.grey[600] : Colors.teal[700],
                                            size: 20,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Card 3: Summary & Invoice-style Ticket Row Layout
                  Card(
                    color: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.0),
                      side: BorderSide(color: Colors.grey[200]!),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.shopping_bag_outlined, color: Colors.teal[700], size: 22),
                                  const SizedBox(width: 8),
                                  Text(
                                    "3. Review & Checkout",
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal[800]),
                                  ),
                                ],
                              ),
                              Text(
                                "Total: \$${cartNotifier.totalPrice.toStringAsFixed(2)}",
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal[900]),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (cart.isEmpty)
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 24.0),
                                child: Text(
                                  "No slots selected. Tap available slots above.",
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                            )
                          else ...[
                            // Invoice Box Style
                            Container(
                              padding: const EdgeInsets.all(12.0),
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                border: Border.all(color: Colors.grey[200]!),
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                              child: ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: cart.length,
                                separatorBuilder: (context, index) => Divider(color: Colors.grey[200]),
                                itemBuilder: (context, index) {
                                  final item = cart[index];
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                item.serviceName,
                                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                "${item.date} @ ${item.startTime} | ${item.caregiverName}",
                                                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          "\$${item.price.toStringAsFixed(2)}",
                                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[800], fontSize: 14),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                          onPressed: () {
                                            cartNotifier.removeItem(item);
                                          },
                                          visualDensity: VisualDensity.compact,
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: FilledButton.icon(
                                onPressed: isCheckingOut ? null : handleCheckout,
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.teal[700],
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10.0),
                                  ),
                                ),
                                icon: isCheckingOut
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.lock_outline, size: 18),
                                label: Text(
                                  isCheckingOut ? "Processing Transaction..." : "Atomically Book All",
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // History Module: Your Scheduled Appointments
                  Card(
                    color: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.0),
                      side: BorderSide(color: Colors.grey[200]!),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.history, color: Colors.teal[700], size: 22),
                              const SizedBox(width: 8),
                              Text(
                                "Your Scheduled Appointments",
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal[800]),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          historyAsync.when(
                            data: (bookings) {
                              if (bookings.isEmpty) {
                                return const Center(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(vertical: 24.0),
                                    child: Text(
                                      "No confirmed bookings found.",
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  ),
                                );
                              }
                              return ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: bookings.length,
                                separatorBuilder: (context, index) => const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final booking = bookings[index];
                                  final startTime = DateTime.parse(booking['start_time']);
                                  final endTime = DateTime.parse(booking['end_time']);
                                  final formattedBookingDate = "${startTime.year}-${startTime.month.toString().padLeft(2, '0')}-${startTime.day.toString().padLeft(2, '0')}";
                                  final formattedStart = "${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}";
                                  final formattedEnd = "${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}";

                                  return Card(
                                    color: Colors.grey[50],
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8.0),
                                      side: BorderSide(color: Colors.grey[200]!),
                                    ),
                                    margin: EdgeInsets.zero,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
                                      child: Row(
                                        children: [
                                          Icon(Icons.check_circle_outline, color: Colors.green[600], size: 20),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  booking['service_name'],
                                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  "Caregiver: ${booking['caregiver_name']}",
                                                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  "$formattedBookingDate | $formattedStart - $formattedEnd",
                                                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                            loading: () => const Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 24.0),
                                child: CircularProgressIndicator(),
                              ),
                            ),
                            error: (err, stack) => Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 24.0),
                                child: Text(
                                  "Error loading history: $err",
                                  style: const TextStyle(color: Colors.redAccent),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Floating / Hover Overlay status banners for Checkout Outcome
          if (checkoutSuccess)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Card(
                elevation: 6,
                shadowColor: Colors.black26,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    border: Border.all(color: Colors.green[200]!),
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green[700], size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "Success! All bookings have been locked and scheduled successfully.",
                          style: TextStyle(color: Colors.green[900], fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: Colors.green[800]),
                        onPressed: () {
                          setState(() {
                            checkoutSuccess = false;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),

          if (checkoutError != null)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Card(
                elevation: 6,
                shadowColor: Colors.black26,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    border: Border.all(color: Colors.red[200]!),
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Icon(Icons.warning, color: Colors.red[700], size: 28),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (checkoutError!.contains("Conflict") || checkoutError!.contains("past"))
                                  ? "Atomic Transaction Rolled Back:"
                                  : "System Error:",
                              style: TextStyle(color: Colors.red[900], fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              checkoutError!,
                              style: TextStyle(color: Colors.red[800], fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: Colors.red[800]),
                        onPressed: () {
                          setState(() {
                            checkoutError = null;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

