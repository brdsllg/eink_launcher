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
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const FileEntryTile({
    super.key,
    required this.entry,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kRowHeight,
      decoration: BoxDecoration(
        color: isSelected ? Colors.black : null,
        border: const Border(
          bottom: BorderSide(color: Colors.black, width: 0.5),
        ),
      ),
      child: ListTile(
        dense: true,
        title: Text(
          entry.isDirectory ? '${entry.name}/' : entry.name,
          style: TextStyle(
            // File names are bold so they stand out; folder names stay regular.
            fontWeight: entry.isDirectory ? FontWeight.normal : FontWeight.bold,
            color: isSelected ? Colors.white : null,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        trailing: isSelected
            ? Icon(
                entry.isDirectory ? Icons.folder : Icons.insert_drive_file,
                color: Colors.white,
                size: 26,
              )
            : (entry.isDirectory
                ? const Icon(Icons.folder, color: Colors.grey, size: 26)
                : Text(
                    entry.sizeLabel ?? '',
                    style: const TextStyle(fontSize: 14, color: Colors.black),
                  )),
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }
}
