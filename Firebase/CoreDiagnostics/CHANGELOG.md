# v0.1.0
- Initial Release--for Google-use only. This library collects diagnostics and
usage data for internal use by Firebase. Data gathered by this library will
only be uploaded at most once every 24 hours whilst on mobile data, and more
frequently on wifi if it's available. This library has been integrated as a
weak dependency and can be safely removed by using a non-Cocoapods distribution
method. You can also use the Firebase global data collection flag to opt-out of
collecting this usage data.