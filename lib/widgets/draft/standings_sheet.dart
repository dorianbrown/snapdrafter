import 'package:flutter/material.dart';
import '../../services/draft/draft_state.dart';

/// Shows a bottom sheet with the current tournament standings.
///
/// Players are sorted by match points, then OMW%, then GW%.
/// Top 3 ranks receive gold/silver/bronze coloring.
void showStandingsSheet({
  required BuildContext context,
  required DraftState state,
  required String myDeviceId,
}) {
  final standings = state.standings;

  showModalBottomSheet(
    context: context,
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildSheetHandle(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('Current Standings',
              style: Theme.of(context).textTheme.titleMedium),
        ),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: standings.length,
            itemBuilder: (ctx, index) {
              final rank = index + 1;
              final player = standings[index];
              final isMe = player.deviceId == myDeviceId;
              final omw = state.opponentMatchWinPercent(player.deviceId);
              final gw = player.gameWinPercentage;

              Color? rankColor;
              if (rank == 1) rankColor = Colors.amber;
              if (rank == 2) rankColor = Colors.grey.shade400;
              if (rank == 3) rankColor = Colors.brown.shade300;

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: rankColor ?? Colors.grey.shade200,
                  radius: 16,
                  child: Text(
                    '$rank',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: rank <= 3 ? Colors.black87 : Colors.grey,
                    ),
                  ),
                ),
                title: Row(
                  children: [
                    Flexible(
                      child: Text(
                        player.playerName,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: rank == 1
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                    if (isMe)
                      const Text(' (you)',
                          style:
                              TextStyle(color: Colors.grey, fontSize: 12)),
                    const Spacer(),
                    Text('${player.matchPoints} pts',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
                subtitle: Text(
                  'W-L-D: ${player.matchWins}-${player.matchLosses}-${player.matchDraws}'
                  '  |  OMW: ${(omw * 100).toStringAsFixed(0)}%'
                  '  |  GW: ${(gw * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(fontSize: 11),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

Widget _buildSheetHandle() {
  return Center(
    child: Container(
      width: 32,
      height: 4,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}
