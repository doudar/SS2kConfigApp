import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:async';

class WorkoutScreen extends StatefulWidget {
  final BluetoothDevice device;

  const WorkoutScreen({Key? key, required this.device}) : super(key: key);

  @override
  _WorkoutScreenState createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> ergBlocks = [
{'duration': 10, 'target': 0.5, 'messages': []},
{'duration': 10, 'target': 0.5222222222222223, 'messages': []},
{'duration': 10, 'target': 0.5444444444444444, 'messages': []},
{'duration': 10, 'target': 0.5666666666666667, 'messages': []},
{'duration': 10, 'target': 0.5888888888888889, 'messages': []},
{'duration': 10, 'target': 0.6111111111111112, 'messages': []},
{'duration': 10, 'target': 0.6333333333333333, 'messages': []},
{'duration': 10, 'target': 0.6555555555555556, 'messages': []},
{'duration': 10, 'target': 0.6777777777777778, 'messages': []},
{'duration': 10, 'target': 0.7, 'messages': []},
{'duration': 10, 'target': 0.7222222222222222, 'messages': []},
{'duration': 10, 'target': 0.7444444444444445, 'messages': []},
{'duration': 10, 'target': 0.7666666666666666, 'messages': []},
{'duration': 10, 'target': 0.788888888888889, 'messages': []},
{'duration': 10, 'target': 0.8111111111111111, 'messages': []},
{'duration': 10, 'target': 0.8333333333333334, 'messages': []},
{'duration': 10, 'target': 0.8555555555555556, 'messages': [{'time': 0.0, 'message': 'Nearly at threshold power now.'}]},
{'duration': 10, 'target': 0.8777777777777778, 'messages': [{'time': 0.0, 'message': 'Time for the 4min threshold effort.'}]},
{'duration': 10, 'target': 1.06, 'messages': []},
{'duration': 10, 'target': 1.0716666666666668, 'messages': []},
{'duration': 10, 'target': 1.0833333333333335, 'messages': [{'time': 0.0, 'message': 'The AC efforts step up in power slightly.'}]},
{'duration': 10, 'target': 1.095, 'messages': []},
{'duration': 10, 'target': 1.1066666666666667, 'messages': []},
{'duration': 10, 'target': 1.1183333333333334, 'messages': []},
{'duration': 10, 'target': 1.13, 'messages': []},
{'duration': 10, 'target': 1.1416666666666666, 'messages': []},
{'duration': 10, 'target': 1.1533333333333333, 'messages': []},
{'duration': 10, 'target': 1.165, 'messages': []},
{'duration': 10, 'target': 1.1766666666666667, 'messages': []},
{'duration': 10, 'target': 1.1883333333333332, 'messages': []},
{'duration': 10, 'target': 1.06, 'messages': []},
{'duration': 10, 'target': 1.0716666666666668, 'messages': []},
{'duration': 10, 'target': 1.0833333333333335, 'messages': []},
{'duration': 10, 'target': 1.095, 'messages': []},
{'duration': 10, 'target': 1.1066666666666667, 'messages': []},
{'duration': 10, 'target': 1.1183333333333334, 'messages': []},
{'duration': 10, 'target': 1.13, 'messages': []},
{'duration': 10, 'target': 1.1416666666666666, 'messages': []},
{'duration': 10, 'target': 1.1533333333333333, 'messages': []},
{'duration': 10, 'target': 1.165, 'messages': []},
{'duration': 10, 'target': 1.1766666666666667, 'messages': []},
{'duration': 10, 'target': 1.1883333333333332, 'messages': []},
{'duration': 10, 'target': 1.06, 'messages': []},
{'duration': 10, 'target': 1.0716666666666668, 'messages': []},
{'duration': 10, 'target': 1.0833333333333335, 'messages': []},
{'duration': 10, 'target': 1.095, 'messages': [{'time': 0.0, 'message': 'Ensure you are holding good form on the bike. No rocking shoulders.'}]},
{'duration': 10, 'target': 1.1066666666666667, 'messages': []},
{'duration': 10, 'target': 1.1183333333333334, 'messages': []},
{'duration': 10, 'target': 1.13, 'messages': []},
{'duration': 10, 'target': 1.1416666666666666, 'messages': []},
{'duration': 10, 'target': 1.1533333333333333, 'messages': []},
{'duration': 10, 'target': 1.165, 'messages': []},
{'duration': 10, 'target': 1.1766666666666667, 'messages': []},
{'duration': 10, 'target': 1.1883333333333332, 'messages': []},
{'duration': 10, 'target': 1.06, 'messages': []},
{'duration': 10, 'target': 1.0716666666666668, 'messages': [{'time': 0.0, 'message': 'Aim to maintain the same cadence throughout the effort.'}]},
{'duration': 10, 'target': 1.0833333333333335, 'messages': []},
{'duration': 10, 'target': 1.095, 'messages': []},
{'duration': 10, 'target': 1.1066666666666667, 'messages': []},
{'duration': 10, 'target': 1.1183333333333334, 'messages': []},
{'duration': 10, 'target': 1.13, 'messages': []},
{'duration': 10, 'target': 1.1416666666666666, 'messages': []},
{'duration': 10, 'target': 1.1533333333333333, 'messages': []},
{'duration': 10, 'target': 1.165, 'messages': []},
{'duration': 10, 'target': 1.1766666666666667, 'messages': []},
{'duration': 10, 'target': 1.1883333333333332, 'messages': []},
{'duration': 10, 'target': 1.06, 'messages': []},
{'duration': 10, 'target': 1.0716666666666668, 'messages': []},
{'duration': 10, 'target': 1.0833333333333335, 'messages': []},
{'duration': 10, 'target': 1.095, 'messages': []},
{'duration': 10, 'target': 1.1066666666666667, 'messages': []},
{'duration': 10, 'target': 1.1183333333333334, 'messages': []},
{'duration': 10, 'target': 1.13, 'messages': []},
{'duration': 10, 'target': 1.1416666666666666, 'messages': []},
{'duration': 10, 'target': 1.1533333333333333, 'messages': []},
{'duration': 10, 'target': 1.165, 'messages': []},
{'duration': 10, 'target': 1.1766666666666667, 'messages': []},
{'duration': 10, 'target': 1.1883333333333332, 'messages': []},
{'duration': 10, 'target': 1.21, 'messages': []},
{'duration': 10, 'target': 1.2583333333333333, 'messages': [{'time': 0.0, 'message': 'Aim to hold a similar cadence to the earlier efforts.'}]},
{'duration': 10, 'target': 1.3066666666666666, 'messages': []},
{'duration': 10, 'target': 1.355, 'messages': []},
{'duration': 10, 'target': 1.4033333333333333, 'messages': []},
{'duration': 10, 'target': 1.4516666666666667, 'messages': []},
{'duration': 10, 'target': 1.21, 'messages': []},
{'duration': 10, 'target': 1.2583333333333333, 'messages': []},
{'duration': 10, 'target': 1.3066666666666666, 'messages': []},
{'duration': 10, 'target': 1.355, 'messages': []},
{'duration': 10, 'target': 1.4033333333333333, 'messages': []},
{'duration': 10, 'target': 1.4516666666666667, 'messages': []},
{'duration': 10, 'target': 1.21, 'messages': []},
{'duration': 10, 'target': 1.2583333333333333, 'messages': []},
{'duration': 10, 'target': 1.3066666666666666, 'messages': []},
{'duration': 10, 'target': 1.355, 'messages': []},
{'duration': 10, 'target': 1.4033333333333333, 'messages': []},
{'duration': 10, 'target': 1.4516666666666667, 'messages': []},
{'duration': 60.0, 'target': 0.5, 'messages': [{'time': 50.0, 'message': 'Now for a 1min high power, effort.'}]},
{'duration': 60.0, 'target': 1.09, 'messages': []},
{'duration': 120.0, 'target': 0.5, 'messages': [{'time': 110.0, 'message': 'To prepare for the AC efforts we step up to a 4min threshold effort now.'}]},
{'duration': 240.0, 'target': 0.9, 'messages': []},
{'duration': 180.0, 'target': 0.5, 'messages': [{'time': 90.0, 'message': '4 x 2min efforts followed by 3 x 1min efforts, you will need to stay focused today!'}, {'time': 130.0, 'message': 'This is a very high level of intensity that requires mental and physical perseverance.'}]},
{'duration': 120.0, 'target': 0.5, 'messages': [{'time': 30.0, 'message': 'A short recovery will improve your ability to repeat hard efforts.'}]},
{'duration': 120.0, 'target': 0.5, 'messages': [{'time': 100.0, 'message': 'Just 3 more of these 2min efforts to go.'}]},
{'duration': 120.0, 'target': 0.5, 'messages': [{'time': 100.0, 'message': '2 more to go. '}]},
{'duration': 120.0, 'target': 0.5, 'messages': [{'time': 100.0, 'message': 'Last 2min effort!'}]},
{'duration': 120.0, 'target': 0.5, 'messages': [{'time': 30.0, 'message': 'Just a short rest.'}, {'time': 90.0, 'message': 'In the next set, the efforts are short, but the power is higher.'}]},
{'duration': 120.0, 'target': 0.5, 'messages': [{'time': 60.0, 'message': 'How did that feel? A little harder?'}, {'time': 100.0, 'message': 'Just 2 more efforts to go for the session!'}]},
{'duration': 120.0, 'target': 0.5, 'messages': [{'time': 100.0, 'message': 'Last effort. Make it your best! '}]},
{'duration': 120.0, 'target': 0.5, 'messages': [{'time': 60.0, 'message': 'Well done. That was a big session.'}]},
{'duration': 10, 'target': 0.45, 'messages': []},
{'duration': 10, 'target': 0.45833333333333337, 'messages': []},
{'duration': 10, 'target': 0.4666666666666667, 'messages': []},
{'duration': 10, 'target': 0.47500000000000003, 'messages': [{'time': 0.0, 'message': 'We begin the warm up with a gentle aerobic effort.'}]},
{'duration': 10, 'target': 0.48333333333333334, 'messages': []},
{'duration': 10, 'target': 0.4916666666666667, 'messages': []},
{'duration': 10, 'target': 0.5, 'messages': []},
{'duration': 10, 'target': 0.5083333333333333, 'messages': []},
{'duration': 10, 'target': 0.5166666666666667, 'messages': []},
{'duration': 10, 'target': 0.525, 'messages': []},
{'duration': 10, 'target': 0.5333333333333333, 'messages': []},
{'duration': 10, 'target': 0.5416666666666666, 'messages': []},
{'duration': 10, 'target': 0.55, 'messages': []},
{'duration': 10, 'target': 0.5583333333333333, 'messages': []},
{'duration': 10, 'target': 0.5666666666666667, 'messages': []},
{'duration': 10, 'target': 0.5833333333333334, 'messages': []},
{'duration': 10, 'target': 0.5916666666666667, 'messages': []},
{'duration': 10, 'target': 0.6, 'messages': []},
{'duration': 10, 'target': 0.6083333333333334, 'messages': []},
{'duration': 10, 'target': 0.6166666666666667, 'messages': []},
{'duration': 10, 'target': 0.625, 'messages': []},
{'duration': 10, 'target': 0.6333333333333333, 'messages': []},
{'duration': 10, 'target': 0.6416666666666666, 'messages': []},
{'duration': 10, 'target': 0.65, 'messages': []},
{'duration': 10, 'target': 0.6583333333333333, 'messages': []},
{'duration': 10, 'target': 0.6666666666666667, 'messages': []},
{'duration': 10, 'target': 0.675, 'messages': []},
{'duration': 10, 'target': 0.6833333333333333, 'messages': []},
{'duration': 10, 'target': 0.6916666666666667, 'messages': []},
{'duration': 10, 'target': 0.7, 'messages': []},
{'duration': 10, 'target': 0.7083333333333333, 'messages': []},
{'duration': 10, 'target': 0.7166666666666667, 'messages': []},
{'duration': 10, 'target': 0.7250000000000001, 'messages': []},
{'duration': 10, 'target': 0.7333333333333334, 'messages': []},
{'duration': 10, 'target': 0.75, 'messages': []},
{'duration': 10, 'target': 0.74, 'messages': []},
{'duration': 10, 'target': 0.73, 'messages': []},
{'duration': 10, 'target': 0.72, 'messages': []},
{'duration': 10, 'target': 0.71, 'messages': []},
{'duration': 10, 'target': 0.7, 'messages': []},
{'duration': 10, 'target': 0.69, 'messages': []},
{'duration': 10, 'target': 0.6799999999999999, 'messages': []},
{'duration': 10, 'target': 0.67, 'messages': []},
{'duration': 10, 'target': 0.66, 'messages': []},
{'duration': 10, 'target': 0.65, 'messages': []},
{'duration': 10, 'target': 0.64, 'messages': []},
{'duration': 10, 'target': 0.63, 'messages': []},
{'duration': 10, 'target': 0.62, 'messages': []},
{'duration': 10, 'target': 0.61, 'messages': []},
{'duration': 10, 'target': 0.6, 'messages': []},
{'duration': 10, 'target': 0.59, 'messages': []},
{'duration': 10, 'target': 0.58, 'messages': []},
{'duration': 10, 'target': 0.5700000000000001, 'messages': []},
{'duration': 10, 'target': 0.56, 'messages': []},
{'duration': 10, 'target': 0.55, 'messages': []},
{'duration': 10, 'target': 0.54, 'messages': []},
{'duration': 10, 'target': 0.53, 'messages': []},
{'duration': 10, 'target': 0.52, 'messages': []},
{'duration': 10, 'target': 0.51, 'messages': []},
{'duration': 10, 'target': 0.5, 'messages': []},
{'duration': 10, 'target': 0.49, 'messages': []},
{'duration': 10, 'target': 0.48, 'messages': []},
{'duration': 10, 'target': 0.47, 'messages': []},
{'duration': 10, 'target': 0.46, 'messages': []},
  ];

  int currentBlockIndex = 0;
  bool isPlaying = false;
  double ftp = 250.0;
  double currentErgTarget = 0.0;
  double currentWatts = 0.0;
  double currentCadence = 0.0;
  double currentHeartRate = 0.0;
  double currentSpeed = 0.0;
  double currentDistance = 0.0;
  Duration currentBlockTimeRemaining = Duration.zero;
  Duration totalTimeRemaining = Duration.zero;
  Duration elapsedTime = Duration.zero;
  double maxScrollExtent = 0;
  String inspirationalMessage = '';

  late StreamSubscription<BluetoothConnectionState> connectionStateSubscription;
  late StreamSubscription<bool> isConnectingSubscription;
  late StreamSubscription<bool> isDisconnectingSubscription;
  Timer? _timer;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    setupBleData();
    totalTimeRemaining = ergBlocks.fold(Duration.zero, (total, block) {
      return total + Duration(seconds: block['duration'].toInt());
    });
    currentBlockTimeRemaining = Duration(seconds: ergBlocks[0]['duration'].toInt());
    _animationController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );
    _fadeAnimation = Tween(begin: 0.0, end: 1.0).animate(_animationController);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scrollToCurrentBlock();
      }
    });
  }

  void setupBleData() {
    // Add your BLE setup and connection code here
  }

  void loadZwoFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zwo'],
    );

    if (result != null && result.files.isNotEmpty) {
      PlatformFile file = result.files.first;
      parseZwoFile(file);
    }
  }

  void parseZwoFile(PlatformFile file) {
    final content = utf8.decode(file.bytes!); // Ensure file bytes are not null
    // Parse the ZWO file content and populate the ergBlocks list
    // This is a placeholder. Actual parsing logic will depend on ZWO file format.
    setState(() {
      ergBlocks = [
        {'duration': 60.0, 'target': 0.6},
        {'duration': 120.0, 'target': 0.8},
        {'duration': 90.0, 'target': 1.0},
        // Add more blocks as needed
      ];
      totalTimeRemaining = ergBlocks.fold(Duration.zero, (total, block) {
        return total + Duration(seconds: block['duration'].toInt());
      });
      currentBlockTimeRemaining = Duration(seconds: ergBlocks[0]['duration'].toInt());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _scrollToCurrentBlock();
        }
      });
    });
  }

  void playPauseWorkout() {
    setState(() {
      isPlaying = !isPlaying;
      if (isPlaying) {
        startTimer();
      } else {
        _timer?.cancel();
      }
    });
  }

  void startTimer() {
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        if (currentBlockTimeRemaining.inSeconds > 0) {
          currentBlockTimeRemaining -= Duration(seconds: 1);
          currentErgTarget = ergBlocks[currentBlockIndex]['target'] * ftp;
          checkForMessages();
        } else {
          if (currentBlockIndex < ergBlocks.length - 1) {
            currentBlockIndex++;
            currentBlockTimeRemaining = Duration(seconds: ergBlocks[currentBlockIndex]['duration'].toInt());
            inspirationalMessage = '';
          } else {
            timer.cancel();
            isPlaying = false;
          }
        }
        elapsedTime += Duration(seconds: 1);
        totalTimeRemaining -= Duration(seconds: 1);
        if (mounted) {
          _scrollToCurrentBlock();
        }
      });
    });
  }

  void checkForMessages() {
    if (ergBlocks[currentBlockIndex].containsKey('messages')) {
      List<dynamic> messages = ergBlocks[currentBlockIndex]['messages'];
      for (var message in messages) {
        if (ergBlocks[currentBlockIndex]['duration'] - currentBlockTimeRemaining.inSeconds == message['time']) {
          setState(() {
            inspirationalMessage = message['text'] != null ? message['text'] : "";
            _animationController.forward(from: 0.0);
          });
          Timer(Duration(seconds: 10), () {
            setState(() {
              inspirationalMessage = '';
            });
          });
        }
      }
    }
  }

  void _scrollToCurrentBlock() {
    double offset = 0;
    for (int i = 0; i < currentBlockIndex; i++) {
      offset += ergBlocks[i]['duration'];
    }
    offset += ergBlocks[currentBlockIndex]['duration'] - currentBlockTimeRemaining.inSeconds;
    maxScrollExtent = _scrollController.hasClients ? _scrollController.position.maxScrollExtent : 0;
    double viewWidth = MediaQuery.of(context).size.width;

    double targetOffset = offset - 100;

    if (targetOffset > maxScrollExtent - viewWidth) {
      targetOffset = maxScrollExtent - viewWidth + (offset - maxScrollExtent);
    } else if (targetOffset < 0) {
      targetOffset = offset;
    }

    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        targetOffset,
        duration: Duration(seconds: 1),
        curve: Curves.linear,
      );
    }
  }

  void adjustFtp(double newFtp) {
    setState(() {
      ftp = newFtp;
    });
  }

  void resetWorkout() {
    setState(() {
      currentBlockIndex = 0;
      currentBlockTimeRemaining = Duration(seconds: ergBlocks[0]['duration'].toInt());
      elapsedTime = Duration.zero;
      totalTimeRemaining = ergBlocks.fold(Duration.zero, (total, block) {
        return total + Duration(seconds: block['duration'].toInt());
      });
      if (isPlaying) {
        _timer?.cancel();
        startTimer();
      }
    });
  }

  void skipBlock() {
    setState(() {
      if (currentBlockIndex < ergBlocks.length - 1) {
        currentBlockIndex++;
        currentBlockTimeRemaining = Duration(seconds: ergBlocks[currentBlockIndex]['duration'].toInt());
        if (isPlaying) {
          _timer?.cancel();
          startTimer();
        }
      }
    });
  }

  Color getColorForErgTarget(double target) {
    target = target * ftp; // Convert target percentage to watts
    if (target >= ftp * 1.2) {
      return Color.fromARGB(96, 251, 0, 255);
    } else if (target >= ftp) {
      return Colors.red;
    } else if (target >= ftp * 0.8) {
      return Colors.yellow;
    } else if (target >= ftp * 0.6) {
      return Colors.green;
    } else {
      return Colors.blue;
    }
  }

  void updateCurrentValues(double ergTarget, double watts, double cadence, double heartRate, double speed,
      double distance, Duration blockTimeRemaining, Duration workoutTimeRemaining) {
    setState(() {
      currentErgTarget = ergTarget;
      currentWatts = watts;
      currentCadence = cadence;
      currentHeartRate = heartRate;
      currentSpeed = speed;
      currentDistance = distance;
      currentBlockTimeRemaining = blockTimeRemaining;
      totalTimeRemaining = workoutTimeRemaining;
    });
  }

  @override
  void dispose() {
    connectionStateSubscription.cancel();
    isConnectingSubscription.cancel();
    isDisconnectingSubscription.cancel();
    _timer?.cancel();
    _animationController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Workout Screen"),
      ),
      body: Column(
        children: [
          SizedBox(height: 10),
          ElevatedButton(
            onPressed: loadZwoFile,
            child: Text('Load .zwo File'),
          ),
          SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: playPauseWorkout,
                child: Text(isPlaying ? 'Pause' : 'Play'),
              ),
              SizedBox(width: 10),
              ElevatedButton(
                onPressed: resetWorkout,
                child: Text('Reset'),
              ),
              SizedBox(width: 10),
              ElevatedButton(
                onPressed: skipBlock,
                child: Text('Skip Block'),
              ),
            ],
          ),
          SizedBox(height: 10),
          Slider(
            value: ftp,
            min: 100,
            max: 500,
            divisions: 40,
            label: ftp.round().toString(),
            onChanged: (value) {
              adjustFtp(value);
            },
          ),
          Text('FTP: ${ftp.round()}'),
          // Metrics Display
          Expanded(
            flex: 1,
            child: Stack(
              children: [
                GridView.count(
                  crossAxisCount: 3,
                  childAspectRatio: 2.5,
                  padding: EdgeInsets.all(8.0),
                  children: [
                    buildMetricCard('Power Lap', currentWatts.toInt().toString()),
                    buildMetricCard('Power', currentWatts.toInt().toString() + 'w'),
                    buildMetricCard('Interval Time', formatDuration(currentBlockTimeRemaining)),
                    buildMetricCard('Heart Rate', currentHeartRate.toInt().toString()),
                    buildMetricCard('Target', currentErgTarget.toInt().toString() + 'w'),
                    buildMetricCard('Elapsed Time', formatDuration(elapsedTime)),
                    buildMetricCard('Speed', currentSpeed.toStringAsFixed(1)),
                    buildMetricCard('Cadence', currentCadence.toInt().toString()),
                    buildMetricCard('Distance', currentDistance.toStringAsFixed(1)),
                  ],
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: Container(
                        padding: EdgeInsets.all(8),
                        color: Colors.white.withOpacity(0.8),
                        child: Text(
                          inspirationalMessage,
                          style: TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Progress Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(1.0, 0.0, 1.0, 10.0),
            child: LinearProgressIndicator(
              value: (ergBlocks.isNotEmpty && currentBlockTimeRemaining.inSeconds > 0)
                  ? currentBlockTimeRemaining.inSeconds / ergBlocks[currentBlockIndex]['duration']
                  : 0,
              minHeight: 20.0,
              backgroundColor: Colors.white,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
            ),
          ),
          // ERG Target Preview
          Expanded(
            flex: 1,
            child: Stack(
              children: [
                SingleChildScrollView(
                  clipBehavior: Clip.none,
                  physics: AlwaysScrollableScrollPhysics(),
                  scrollDirection: Axis.horizontal,
                  controller: _scrollController,
                  child: Row(
                    children: ergBlocks.asMap().entries.map((entry) {
                      int index = entry.key;
                      Map<String, dynamic> block = entry.value;
                      final color = getColorForErgTarget(block['target']);
                      return AnimatedBuilder(
                        animation: _animationController,
                        builder: (context, child) {
                          return Container(
                            width: block['duration'].toDouble(),
                            alignment: Alignment.bottomLeft,
                            child: Container(
                              width: block['duration'].toDouble(),
                              height: (block['target'] * 100),
                              color: color,
                              margin: EdgeInsets.symmetric(horizontal: 0),
                              child: Center(
                                child: Text(
                                  '${(block['target'] * ftp).toInt()} W',
                                  style: TextStyle(color: Colors.white, fontSize: 10),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              foregroundDecoration: index == currentBlockIndex
                                  ? BoxDecoration(
                                      color: Colors.black.withOpacity(0.2 * _animationController.value),
                                    )
                                  : null,
                            ),
                          );
                        },
                      );
                    }).toList(),
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: EdgeInsets.all(8),
                    color: Colors.black.withOpacity(0.5),
                    child: Text(
                      '${currentBlockIndex + 1}/${ergBlocks.length}',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildMetricCard(String title, String value) {
    return Card(
      color: Colors.black54,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
            SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(color: Colors.white, fontSize: 24),
            ),
          ],
        ),
      ),
    );
  }

  String formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$hours:$minutes:$seconds";
  }
}
