import 'package:flutter/material.dart';
import '../utils/workout/ride_map.dart';

class RideDrawingField extends StatelessWidget {
  const RideDrawingField({
    super.key,
    required this.initialDrawing,
    required this.onChanged,
    this.label = 'Map for this ride',
  });

  final RideDrawing initialDrawing;
  final ValueChanged<RideDrawing> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<RideDrawing>(
    initialValue: initialDrawing,
    isExpanded: true,
    itemHeight: null,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final drawing in RideDrawing.values)
        DropdownMenuItem(value: drawing, child: Text(drawing.label)),
    ],
    onChanged: (drawing) {
      if (drawing != null) onChanged(drawing);
    },
  );
}
