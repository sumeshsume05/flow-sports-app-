import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/connectivity_state.dart';

/// Some admin actions read the real, current data from the server and then
/// write many things at once (generate a schedule or bracket, reset a sport).
/// With no network they would run on the phone's saved copy — which may be
/// out of date or empty — and queue the writes for later. So they check
/// first. Returns true when the phone is online; otherwise says why nothing
/// happened and returns false.
bool requireOnline(BuildContext context, String what) {
  final offline = Provider.of<ConnectivityState?>(context, listen: false)?.isOffline ?? false;
  if (!offline) return true;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text("You're offline. $what needs a connection — try again when the network is back."),
  ));
  return false;
}
