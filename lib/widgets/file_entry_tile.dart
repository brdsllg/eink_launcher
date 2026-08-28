import 'package:flutter/material.dart';

import '../constants.dart';
import '../models/file_entry.dart';

/// A single row representation of a file or folder in the file browser list.
///
/// Extracted as a separate [StatelessWidget] so Flutter can optimize element
/// diffing and rebuild only modified rows when selection or status updates.
class FileEntryTile extends StatelessWidget {
  final FileEntry entry;
  final bool isSelected;
  final bool isOpening;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final double height;

  const FileEntryTile({
    super.key,
    required this.entry,
    required this.isSelected,
    this.isOpening = false,
    required this.onTap,
    required this.onLongPress,
    this.height = kRowHeight,
  });

  @override
  Widget build(BuildContext context) {
    final inverted = isSelected || isOpening;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: inverted ? Colors.black : null,
        border: const Border(
          bottom: BorderSide(color: Colors.black, width: 0.5),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
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
                ),
              ),
              const SizedBox(width: 12),
              if (inverted)
                Icon(
                  entry.isDirectory ? Icons.folder : Icons.insert_drive_file,
                  color: Colors.white,
                  size: (height * 0.48).clamp(22.0, 30.0).toDouble(),
                )
              else if (entry.isDirectory)
                Icon(
                  Icons.folder,
                  color: Colors.grey,
                  size: (height * 0.48).clamp(22.0, 30.0).toDouble(),
                )
              else
                Text(
                  entry.sizeLabel ?? '',
                  style: TextStyle(
                    fontSize: (height * 0.28).clamp(13.0, 17.0).toDouble(),
                    height: 1,
                    color: Colors.black,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
