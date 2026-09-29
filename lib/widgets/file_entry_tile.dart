import 'package:flutter/material.dart';

import '../constants.dart';
import '../models/file_entry.dart';
import 'inverting_ink_well.dart';

/// A single row representation of a file or folder in the file browser list.
///
/// Extracted as a separate [StatelessWidget] so Flutter can optimize element
/// diffing and rebuild only modified rows when selection or status updates.
class FileEntryTile extends StatelessWidget {
  final FileEntry entry;
  final bool isSelected;
  final bool isOpening;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double height;

  /// Optional short note shown under the size/folder marker in the right-hand
  /// cell — the Recycle Bin uses it for the days left before an item is purged.
  final String? subLabel;

  const FileEntryTile({
    super.key,
    required this.entry,
    required this.isSelected,
    this.isOpening = false,
    required this.onTap,
    required this.onLongPress,
    this.height = kRowHeight,
    this.subLabel,
  });

  // A bounded metadata column keeps sizes and folder markers aligned while
  // leaving the filename all remaining room, especially on a narrow device.
  static double metadataWidthFor(double width) => width < 480 ? 72 : 88;

  @override
  Widget build(BuildContext context) {
    final inverted = isSelected || isOpening;
    final iconSize = (height * 0.48).clamp(22.0, 30.0).toDouble();
    final note = subLabel;
    return InvertingInkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: inverted ? Colors.black : Colors.white,
          border: const Border(bottom: BorderSide(color: Colors.black)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    entry.isDirectory ? '${entry.name}/' : entry.name,
                    style: TextStyle(
                      fontSize: (height * 0.44).clamp(16.0, 26.0).toDouble(),
                      height: 1,
                      // File names are bold so they stand out; folder names stay
                      // regular.
                      fontWeight: entry.isDirectory
                          ? FontWeight.normal
                          : FontWeight.bold,
                      color: inverted ? Colors.white : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ),
              Container(
                width: metadataWidthFor(constraints.maxWidth),
                height: height,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: inverted ? Colors.white : Colors.black,
                    ),
                  ),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (inverted)
                        Icon(
                          entry.isDirectory
                              ? Icons.folder
                              : Icons.insert_drive_file,
                          color: Colors.white,
                          size: iconSize,
                        )
                      else if (entry.isDirectory)
                        Icon(Icons.folder, color: Colors.grey, size: iconSize)
                      else
                        Text(
                          entry.sizeLabel ?? '',
                          style: TextStyle(
                            fontSize: (height * 0.28)
                                .clamp(13.0, 17.0)
                                .toDouble(),
                            height: 1,
                            color: Colors.black,
                          ),
                        ),
                      if (note != null)
                        Text(
                          note,
                          style: TextStyle(
                            fontSize: (height * 0.24)
                                .clamp(11.0, 14.0)
                                .toDouble(),
                            height: 1.2,
                            color: inverted ? Colors.white : Colors.black,
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
    );
  }
}
