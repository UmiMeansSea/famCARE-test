import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'cart_provider.dart';

// Configurable API Base URL
const String baseUrl = "http://192.168.1.3:8000";

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
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Banners for Success/Failure
            if (checkoutSuccess)
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    border: Border.all(color: Colors.green[200]!),
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline, color: Colors.green[700], size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "Success! All bookings have been locked and scheduled successfully.",
                          style: TextStyle(color: Colors.green[900], fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            if (checkoutError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    border: Border.all(color: Colors.red[200]!),
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline, color: Colors.red[700], size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Atomic Transaction Rolled Back:",
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
                    ],
                  ),
                ),
              ),

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
                          "Choose Patient & Service",
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal[800]),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      decoration: InputDecoration(
                        labelText: "Select Patient",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                      ),
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
                          "Available Windows",
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
                            color: isAlreadyInCart ? Colors.grey[100] : Colors.teal[50],
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10.0),
                              side: BorderSide(
                                color: isAlreadyInCart ? Colors.grey[300]! : Colors.teal[100]!,
                              ),
                            ),
                            child: InkWell(
                              onTap: isAlreadyInCart
                                  ? null
                                  : () {
                                      if (selectedService != null) {
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
                                              color: isAlreadyInCart ? Colors.grey[600] : Colors.teal[900],
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
                                      isAlreadyInCart ? Icons.check_circle : Icons.add_circle_outline,
                                      color: isAlreadyInCart ? Colors.grey[400] : Colors.teal[700],
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

            // Card 3: Summary & Ticket Row Layout
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
                              "Your Cart",
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
                            "Cart is empty. Select slots above to populate.",
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    else ...[
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: cart.length,
                        separatorBuilder: (context, index) => Divider(color: Colors.grey[100]),
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
                                        "${item.date} @ ${item.startTime} | Caregiver: ${item.caregiverName}",
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
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: FilledButton.icon(
                          onPressed: handleCheckout,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.teal[700],
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10.0),
                            ),
                          ),
                          icon: const Icon(Icons.lock_outline, size: 18),
                          label: const Text(
                            "Atomically Book All",
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
