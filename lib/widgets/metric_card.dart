import 'package:flutter/material.dart';

class MetricBox extends StatefulWidget {
  final String value;
  final String label;

  const MetricBox({
    Key? key,
    this.value = '',
    required this.label,
  }) : super(key: key);

  @override
  _MetricBoxState createState() => _MetricBoxState();
}

class _MetricBoxState extends State<MetricBox> {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 65,
      height: 65,
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 226, 226, 226),
        borderRadius: BorderRadius.circular(14.0),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            widget.value,
            style: const TextStyle(
              fontSize: 22,
            ),
          ),
          const SizedBox(height: 4.0),
          Text(
            widget.label,
            style: const TextStyle(
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }
}
