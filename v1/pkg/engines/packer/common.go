/*
Copyright 2019 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package packer

import (
	"errors"
	"fmt"
	"os"
	"reflect"
	"strings"

	"github.com/fatih/structs"
)

func GetFieldNameByTags(v interface{}) map[string]reflect.Type {
	names := make(map[string]reflect.Type)

	ifv := reflect.ValueOf(v)
	ift := reflect.TypeOf(v)

	for i := 0; i < ift.NumField(); i++ {
		v := ifv.Field(i)
		switch v.Kind() {
		case reflect.Struct:
			if v.CanInterface() {
				for k, _ := range GetFieldNameByTags(v.Interface()) {
					names[k] = v.Type()
				}
			}
		default:
			for _, tagName := range []string{"structs", "json", "yaml", "mapstructure"} {
				tagValue := ift.Field(i).Tag.Get(tagName)
				if tagValue != "" {
					names[strings.Split(tagValue, ",")[0]] = v.Type()
				}
			}
		}
	}
	return names
}

func sanitizeMap(from map[interface{}]interface{}) map[string]interface{} {
	to := make(map[string]interface{})
	for k, v := range from {
		to[fmt.Sprintf("%s", k)] = v
	}
	return to
}

func sanitizeNestedSlice(from []interface{}) []interface{} {
	var to []interface{}
	for _, v := range from {
		switch v.(type) {
		case []interface{}:
			to = append(to, sanitizeNestedSlice(v.([]interface{})))
		case map[string]interface{}:
			to = append(to, sanitizeNestedMap(v.(map[string]interface{})))
		case map[interface{}]interface{}:
			to = append(to, sanitizeNestedMap(sanitizeMap(v.(map[interface{}]interface{}))))
		default:
			to = append(to, v)
		}
	}
	return to
}

func sanitizeNestedMap(m map[string]interface{}) map[string]interface{} {
	to := make(map[string]interface{})
	for k, v := range m {
		switch v.(type) {
		case []interface{}:
			to[k] = sanitizeNestedSlice(v.([]interface{}))
		case map[string]interface{}:
			to[k] = sanitizeNestedMap(v.(map[string]interface{}))
		case map[interface{}]interface{}:
			to[k] = sanitizeNestedMap(sanitizeMap(v.(map[interface{}]interface{})))
		default:
			to[k] = v
		}
	}
	return to
}

func mergeStruct(m1 map[string]interface{}, m2 interface{}) map[string]interface{} {
	return merge(m1, structs.Map(m2))
}

func merge(m1, m2 map[string]interface{}) map[string]interface{} {
	for k, v := range m2 {
		m1[k] = v
	}
	return m1
}

func ExtractTo(dst string) error {
	if dst == "/" || dst == "" {
		return errors.New("Must specify a destination")
	}
	os.RemoveAll(dst)
	// // set up a new box by giving it a name and an optional (relative) path to a folder on disk:
	// box := packr.New("ansible", "../../images/capi/ansible")

	// if err := box.Walk(func(path string, file packd.File) error {
	// 	to := dst + "/" + path
	// 	// log.Debugf("Extracting %s\n", to)
	// 	info, _ := file.FileInfo()
	// 	_, err := files.CopyFromReader(file, to, info.Mode())
	// 	if err != nil {
	// 		return err
	// 	}
	// 	return nil
	// }); err != nil {
	// 	return err
	// }
	return nil
}
