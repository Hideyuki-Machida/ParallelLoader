//
//  Loader.swift
//  ParallelLoader
//
//  Created by machida hideyuki on 2015/07/13.
//  Copyright © 2015年 machida hideyuki. All rights reserved.
//

import Foundation

public class ParallelLoader: NSObject {

	public static var sessionConfiguration: URLSessionConfiguration = { () -> URLSessionConfiguration in
		var conf: URLSessionConfiguration = URLSessionConfiguration.default
		conf.allowsCellularAccess = true
		conf.timeoutIntervalForRequest = 30
		conf.timeoutIntervalForResource = 600
		return conf
	}()
	
	private static var _items: [String: ParallelLoader.Item] = [:]
	
	/// request url
	/// :param: urlString
	/// :param: dir
	/// :returns: ParallelLoader.Item instance
	public static func request(urlString: String, cacheDir: String? = nil, sessionConfiguration: URLSessionConfiguration? = nil) -> ParallelLoader.Item {
		if let cacheDir: String = cacheDir {
			if let data: NSData = self._getDataInDirectory(url: urlString, cacheDir: cacheDir) {
				return ParallelLoader.Item(data: data)
			}
		}
		return setItem(urlString: urlString, cacheDir: cacheDir)
	}

	public static func deleteCache(urlString: String, cacheDir: String) {
		do {
			guard let fileName: String = NSURL(string: urlString)?.lastPathComponent else { return }
			
			let filePath: String = "\(cacheDir)/\(fileName)"
			try FileManager.default.removeItem(atPath: filePath)
		} catch {
		}
	}
	
	// MARK: public fuc
	
	/// :param: url
	/// :param: dir
	/// :returns: ParallelLoader.Item instance
	public static func setItem(urlString: String, cacheDir: String? = nil, sessionConfiguration: URLSessionConfiguration? = nil) -> ParallelLoader.Item {
		if let item: ParallelLoader.Item = self._items[ urlString ] {
			return item
		} else {
			let item: ParallelLoader.Item = ParallelLoader.Item(
				urlString: urlString,
				cacheDir: cacheDir,
				sessionConfiguration: sessionConfiguration ?? self.sessionConfiguration,
				complete: { (key: String) -> Void in
					_items.removeValue(forKey: key)
			})
			self._items[urlString] = item
			return item
		}
	}
	
	/// :param: urlString
	public static func suspend(urlString: String) {
		if let item: ParallelLoader.Item = self._items[urlString] {
			item.suspend()
		}
	}
	
	/// :param: urlString
	public static func suspendAll() {
		for (_, value) in self._items {
			value.suspend()
		}
	}
	
	/// :param: urlString
	public static func resume(urlString: String) {
		if let item: ParallelLoader.Item = self._items[urlString] {
			item.resume()
		}
	}
	
	/// :param: urlString
	public static func resumeAll() {
		for (_, value) in self._items {
			value.resume()
		}
	}
	
	public static func cancel(url: String) {
	}
	public static func cancelAll() {
	}

	
	/// :param: url
	/// :param: dir
	/// :returns: ParallelLoader.Item instance
	private static func _getDataInDirectory(url: String, cacheDir: String) -> NSData? {
		do {
			guard let fileName: String = NSURL(string: url)?.lastPathComponent else {
				return nil
			}
			
			try FileManager.default.createDirectory(atPath: "\(cacheDir)" , withIntermediateDirectories: true, attributes: nil)
			let filePath: String = "\(cacheDir)/\(fileName)"
			
			if let data: NSData = NSData(contentsOfFile: filePath) {
				//data in directory
				return data
			}
		} catch {
			return nil
		}
		return nil
	}

	deinit {
		//print("deinit ParallelLoader")
	}
}

extension ParallelLoader {
	public class Item: NSObject, URLSessionDownloadDelegate {

		public var urlString: String = ""
		public var cacheDir: String?
		public var data: NSData?

		// MARK: Itrem var

		private var _sessionConfiguration: URLSessionConfiguration?
		private var _session: URLSession?
		private var _task: URLSessionDownloadTask?
		private var _cb: ((_ key: String) -> Void)?
		private var _successCallBacks: [(_ data: NSData) -> Void] = []
		private var _errorCallBacks: [(_ error: LoaderError) -> Void] = []
		private var _progressCallBacks: [(_ progressItem: ProgressItem) -> Void] = []
		
		
		// MARK: Itrem initializer

		init(urlString: String, cacheDir: String?, sessionConfiguration: URLSessionConfiguration, complete: @escaping (_ key: String) -> Void) {
			super.init()
			self.urlString = urlString
			self.cacheDir = cacheDir
			self._cb = complete
			self._sessionConfiguration = sessionConfiguration

			self._session = URLSession(configuration: self._sessionConfiguration!, delegate: self, delegateQueue: nil)
		}
		
		init(data: NSData) {
			super.init()
			self.data = data
		}
		
		@discardableResult
		public func progress(progress: @escaping (_ progressItem: ProgressItem) -> Void) -> ParallelLoader.Item {
			self._progressCallBacks.append(progress)
			return self
		}
		
		@discardableResult
		public func error(error: @escaping (_ error: LoaderError) -> Void) -> ParallelLoader.Item {
			self._errorCallBacks.append(error)
			return self
		}
		
		@discardableResult
		public func success(success: @escaping (_ data: NSData) -> Void) -> Void {
			self._successCallBacks.append(success)

			if self.data != nil {
				self._success(data: self.data!)
			} else {
				self._load()
			}
		}

		public func suspend() {
			self._task?.suspend()
		}

		public func resume() {
			self._task?.resume()
		}

		public func remove() {
			self._sessionConfiguration = nil
			self.data = nil

			self._task?.cancel()
			self._task = nil

			self._session?.finishTasksAndInvalidate()
			self._session = nil
			
			self._successCallBacks.removeAll()
			self._errorCallBacks.removeAll()
			self._progressCallBacks.removeAll()

			self._cb?(self.urlString)
		}

		private func _load() {
			guard let session: URLSession = self._session else{
				self._error(error: LoaderError.sessionError)
				return
			}
			self._task = session.downloadTask(with: NSURL(string: self.urlString)! as URL)
			self._task?.resume()
		}

		
		// MARK: Itrem NSURLSessionDownloadDelegate
		
		public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
			let progressItem: ProgressItem = ProgressItem(bytesWritten: bytesWritten, totalBytesWritten: totalBytesWritten, totalBytesExpectedToWrite: totalBytesExpectedToWrite)
			DispatchQueue.main.sync( execute: {
				self._progressCallBacks.forEach { $0(progressItem) }
			})
		}
		
		public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
			DispatchQueue.main.sync( execute: {
				self._success(location: location)
			})
		}
		
		public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
			self._session?.finishTasksAndInvalidate()
			if let error: NSError = error as? NSError {
				DispatchQueue.main.sync( execute: {
					switch error.code {
					case NSURLErrorTimedOut: self._error(error: LoaderError.timeoutError)
					default: self._error(error: LoaderError.downLoadError)
					}
				})
			}
		}
		
		
		// MARK: Itrem private
		
		private func _success(data: NSData) {
			self._successCallBacks.forEach { $0(data) }
			self._complete()
		}
		
		private func _success(location: URL) {
			
			guard let data: NSData = NSData(contentsOf: location) else{
				self._error(error: LoaderError.dataError)
				return
			}
			
			if let dir: String = self.cacheDir {
				if let fileName: String = NSURL(string: self.urlString)?.lastPathComponent {
					let filePath: String = "\(dir)/\(fileName)"
					data.write(toFile: filePath, atomically: true)
				}
			}
			
			self._successCallBacks.forEach { $0(data) }
			self._complete()
		}
		
		private func _error(error: LoaderError) {
			self._errorCallBacks.forEach { $0(error) }
			self._complete()
		}
		
		private func _complete() {
			self._cb?(self.urlString)
			self.remove()
		}
		
		deinit {
			//print("deinit ParallelLoader.Item")
			self.remove()
		}
		
	}
}

extension ParallelLoader {
	public struct ProgressItem {
		public let bytesWritten: Int64
		public let totalBytesWritten: Int64
		public let totalBytesExpectedToWrite: Int64
		init(bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
			self.bytesWritten = bytesWritten
			self.totalBytesWritten = totalBytesWritten
			self.totalBytesExpectedToWrite = totalBytesExpectedToWrite
		}
	}
}

extension ParallelLoader {
	public enum LoaderError {
		case sessionError
		case timeoutError
		case downLoadError
		case dataError
	}
}

