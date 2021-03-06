import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:tflite/tflite.dart';
import 'package:object_detection/widgets/box.dart';
import 'package:object_detection/widgets/camera.dart';
import 'dart:math' as math;

List<CameraDescription> cameras;

Future<void> main() async {
  // initialize the cameras when the app starts
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  // running the app
  runApp(MaterialApp(
    home: MyApp(),
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(),
  ));
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static const String ssd = "SSD MobileNet";
  static const String yolov2 = "Tiny YOLOv2";
  String model = ssd;
  File _image;
  Color objectAreaColor=Colors.red;
  List _recognitions;
  bool _busy;
  double _imageWidth, _imageHeight;
  final picker = ImagePicker();

  bool _isLive = false;
  List<dynamic> _liveRecognitions;
  int _liveImageHeight = 0;
  int _liveImageWidth = 0;
  initCameras() async {}
  setRecognitions(recognitions, imageHeight, imageWidth) {
    setState(() {
      _liveRecognitions = recognitions;
      _liveImageHeight = imageHeight;
      _liveImageWidth = imageWidth;
    });
  }

  // this function loads the model
  loadModel() async {
    Tflite.close();
    try {
      String res;
      if (model == yolov2) {
        res = await Tflite.loadModel(
          model: "assets/yolov2_tiny.tflite",
          labels: "assets/labels.txt",
        );
      } else if(model == ssd){
        res = await Tflite.loadModel(
          model: "assets/ssd_mobilenet.tflite",
          labels: "assets/ssd_mobilenet.txt",
        );
      }
      print(res);
    } on PlatformException {
      print("Something went completely wrong! ");
    }
  }

  // Function for detecting objects in the image
  detectObject(File image) async {
    if (image == null) return;

    if (model == yolov2) {
      await yolov2Tiny(image);
    } else if(model == ssd){
      await ssdMobileNet(image);
    }
    FileImage(image)
        .resolve(ImageConfiguration())
        .addListener((ImageStreamListener((ImageInfo info, bool b) {
      setState(() {
        _imageWidth = info.image.width.toDouble();
        _imageHeight = info.image.height.toDouble();
      });
    })));

    setState(() {
      _image = image;
      _busy = false;
    });
  }
  yolov2Tiny(File image) async {
    var recognitions = await Tflite.detectObjectOnImage(
        path: image.path,
        model: "YOLO",
        threshold: 0.3,
        imageMean: 0.1,
        imageStd: 255.0,
        numResultsPerClass: 10);

    setState(() {
      _recognitions = recognitions;
    });
  }
  ssdMobileNet(File image) async {
    var recognitions = await Tflite.detectObjectOnImage(
        path: image.path, numResultsPerClass: 10);

    setState(() {
      _recognitions = recognitions;
    });
  }
  @override
  void initState() {
    super.initState();
    _busy = true;
    loadModel().then((val) {
      {
        setState(() {
          _busy = false;
        });
      }
    });
  }

  // Displaying the bounding boxes over the detected objects
  List<Widget> renderBoxes(Size screen) {
    if (_recognitions == null) return [];
    if (_imageWidth == null || _imageHeight == null) return [];

    double factorX = screen.width;
    double factorY = _imageHeight / _imageHeight * screen.width;

    Color blue = Colors.blue;

    return _recognitions.map((re) {
      return Container(
        child: Positioned(
            left: re["rect"]["x"] * factorX,
            top: re["rect"]["y"] * factorY,
            width: re["rect"]["w"] * factorX,
            height: re["rect"]["h"] * factorY,
            child: ((re["confidenceInClass"] > 0.50))
                ? Container(
              decoration: BoxDecoration(
                  border: Border.all(
                    color: blue,
                    width: 3,
                  )),
              child: Text(
                "${re["detectedClass"]} ${(re["confidenceInClass"] * 100).toStringAsFixed(0)}%",
                style: TextStyle(
                  background: Paint()..color = blue,
                  color: Colors.white,
                  fontSize: 15,
                ),
              ),
            )
                : Container()),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    Size size = MediaQuery.of(context).size;

    List<Widget> galleryChildren = [];

    galleryChildren.add(Positioned(
      // using ternary operator
      child: _image == null
          ? Container(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text("Select an Image or Activate Real Time Detection"),
          ],
        ),
      )
          : // if not null then
      Container(child: Image.file(_image)),
    ));

    galleryChildren.addAll(renderBoxes(size));

    if (_busy) {
      galleryChildren.add(Center(
        child: CircularProgressIndicator(),
      ));
    }
    Size screen = MediaQuery.of(context).size;

    return Scaffold(
      appBar: AppBar(title: Text('Object Detection')),
      floatingActionButton: _isLive
          ? FloatingActionButton(
          heroTag: "Fltbtn3",
          backgroundColor: Colors.white,
          child: Icon(Icons.arrow_back),
          onPressed: () {
            setState(() {
              _isLive = false;
            });
          })
          : Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          FloatingActionButton(
              heroTag: "Fltbtn2",
              backgroundColor: Colors.white,
              child: Icon(Icons.camera_alt),
              onPressed: () {
                setState(() {
                  _isLive = true;
                });
              }),
          SizedBox(
            width: 10,
          ),
          FloatingActionButton(
            heroTag: "Fltbtn1",
            backgroundColor: Colors.white,
            child: Icon(Icons.photo),
            onPressed: getImageFromGallery,
          ),
        ],
      ),
      body: Container(
        alignment: Alignment.center,
        child: Stack(
          children: _isLive
              ? <Widget>[
            CameraFeed(cameras, setRecognitions),
            Box(
              _liveRecognitions == null ? [] : _liveRecognitions,
              math.max(_liveImageHeight, _liveImageWidth),
              math.min(_liveImageHeight, _liveImageWidth),
              screen.height,
              screen.width,
            ),
          ]
              : galleryChildren,
        ),
      ),
    );
  }

  // gets image from gallery and runs detectObject
  Future getImageFromGallery() async {
    final pickedFile = await picker.getImage(source: ImageSource.gallery);
    setState(() {
      if (pickedFile != null) {
        _image = File(pickedFile.path);
      } else {
        print("No Image Selected");
      }
    });
    detectObject(_image);
  }
}